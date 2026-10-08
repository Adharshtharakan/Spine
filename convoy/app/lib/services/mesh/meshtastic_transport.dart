import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mesh_service.dart';
import 'meshtastic_proto.dart';

/// Long-range link: a Meshtastic LoRa node in each vehicle, paired to the
/// phone over Bluetooth.
///
/// Phones alone cannot reach a car several kilometres away without towers.
/// A $25–40 LoRa node (Heltec V3, RAK WisBlock, LilyGO T-Echo…) typically
/// reaches 2–10 km car-to-car on roads (15 km+ line of sight with an
/// external antenna), and every node rebroadcasts what it hears, so the
/// convoy's own radios form a mesh that stretches with the convoy.
///
/// The app sends its (already encrypted) frames as PRIVATE_APP packets;
/// the radio is a dumb pipe and never sees plaintext.
class MeshtasticTransport implements MeshTransport {
  MeshtasticTransport(this.deviceId);

  final String deviceId;

  static const _prefsKey = 'meshtastic.device';

  static Future<String?> savedDevice() async => (await SharedPreferences.getInstance()).getString(_prefsKey);
  static Future<void> saveDevice(String? id) async {
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove(_prefsKey);
    } else {
      await p.setString(_prefsKey, id);
    }
  }

  @override
  String get id => 'lora';

  @override
  int get maxPayload => Meshtastic.maxPayload;

  /// LoRa airtime is scarce (≈1 kbps, duty-cycle limits in some regions):
  /// positions go out every 30 s, or sooner on a big change (see MeshService).
  @override
  Duration get positionInterval => const Duration(seconds: 30);

  /// The radio firmware already floods packets across nodes.
  @override
  bool get floods => true;

  final _events = StreamController<MeshEvent>.broadcast();
  @override
  Stream<MeshEvent> get events => _events.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _heartbeat;
  bool _running = false;
  bool _draining = false;
  final _rng = Random();

  /// Radio node ids heard recently → last time, for the peer count.
  final Map<int, DateTime> _heard = {};

  final status = StreamController<RadioStatus>.broadcast();
  RadioStatus _status = RadioStatus.disconnected;
  RadioStatus get currentStatus => _status;

  void _setStatus(RadioStatus s) {
    _status = s;
    status.add(s);
    _emitPeers();
  }

  @override
  Future<void> start({required String tripTag, required String endpointName}) async {
    if (_running) return;
    _running = true;
    unawaited(_connectLoop());
  }

  Future<void> _connectLoop() async {
    var backoff = 2;
    while (_running) {
      try {
        await _connect();
        backoff = 2;
        // Stay here until the link drops.
        await _device!.connectionState.firstWhere((s) => s == BluetoothConnectionState.disconnected);
      } catch (_) {
        // Radio switched off, out of BLE range of the phone, or busy.
      }
      _teardown();
      if (!_running) break;
      _setStatus(RadioStatus.reconnecting);
      await Future<void>.delayed(Duration(seconds: backoff));
      backoff = min(backoff * 2, 30);
    }
  }

  Future<void> _connect() async {
    _setStatus(RadioStatus.connecting);
    final d = BluetoothDevice.fromId(deviceId);
    _device = d;
    await d.connect(timeout: const Duration(seconds: 20), mtu: 512);
    final services = await d.discoverServices();
    final svc = services.firstWhere((s) => s.uuid == Guid(Meshtastic.serviceUuid));
    BluetoothCharacteristic ch(String uuid) => svc.characteristics.firstWhere((c) => c.uuid == Guid(uuid));
    _toRadio = ch(Meshtastic.toRadioUuid);
    _fromRadio = ch(Meshtastic.fromRadioUuid);
    final fromNum = ch(Meshtastic.fromNumUuid);

    await fromNum.setNotifyValue(true);
    _subs.add(fromNum.onValueReceived.listen((_) => _drain()));

    // Handshake: ask for config, then drain until the node has sent it all.
    await _toRadio!.write(Meshtastic.toRadioWantConfig(_rng.nextInt(0x7FFFFFFF)));
    await _drain();
    _heartbeat = Timer.periodic(const Duration(minutes: 5), (_) {
      _toRadio?.write(Meshtastic.toRadioHeartbeat()).catchError((_) {});
    });
    _setStatus(RadioStatus.connected);
  }

  /// FromRadio is a queue: read until the node returns an empty value.
  Future<void> _drain() async {
    if (_draining || _fromRadio == null) return;
    _draining = true;
    try {
      while (true) {
        final v = await _fromRadio!.read();
        if (v.isEmpty) break;
        final msg = Meshtastic.decodeFromRadio(Uint8List.fromList(v));
        final p = msg.packet;
        if (p != null && p.portnum == Meshtastic.privateAppPort && p.payload.isNotEmpty) {
          _heard[p.from] = DateTime.now();
          _emitPeers();
          _events.add(MeshPayload(p.payload, transport: id, source: 'lora:${p.from}'));
        }
      }
    } catch (_) {
      // Link dropped mid-read; the connect loop recovers.
    } finally {
      _draining = false;
    }
  }

  void _emitPeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _heard.removeWhere((_, t) => t.isBefore(cutoff));
    _events.add(MeshPeers(_status == RadioStatus.connected ? _heard.length : 0, transport: id));
  }

  @override
  Future<void> broadcast(Uint8List bytes, {required bool reliable}) async {
    final ch = _toRadio;
    if (ch == null || _status != RadioStatus.connected) return;
    try {
      await ch.write(Meshtastic.toRadioPacket(bytes, packetId: _rng.nextInt(0x7FFFFFFF) + 1));
    } catch (_) {}
  }

  void _teardown() {
    _heartbeat?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _toRadio = null;
    _fromRadio = null;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _teardown();
    await _device?.disconnect();
    _setStatus(RadioStatus.disconnected);
  }
}

enum RadioStatus { disconnected, connecting, connected, reconnecting }

/// Finds nearby Meshtastic nodes for pairing.
Stream<List<ScanResult>> scanForRadios() async* {
  await FlutterBluePlus.startScan(
    withServices: [Guid(Meshtastic.serviceUuid)],
    timeout: const Duration(seconds: 15),
  );
  yield* FlutterBluePlus.scanResults;
}
