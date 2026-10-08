import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/social.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';
import 'position_frame.dart';

/// Peer-to-peer fallback for when cellular coverage disappears.
///
/// Android uses Google Nearby Connections (`P2P_CLUSTER`: Bluetooth, BLE and
/// Wi-Fi Direct chosen automatically); iOS uses MultipeerConnectivity
/// (Bluetooth + peer-to-peer Wi-Fi). Both sit behind the `convoy/mesh`
/// platform channel with the same contract, implemented in
/// `android/.../ConvoyMeshPlugin.kt` and `ios/Runner/ConvoyMeshPlugin.swift`.
///
/// Party isolation carries over from the cloud: peers only connect when they
/// advertise the same trip tag, and every frame carries an HMAC keyed by a
/// secret only trip members hold, so a stranger running Convoy nearby can
/// neither read our convoy's chat nor inject fake positions.
class MeshService {
  MeshService({
    required this.tripId,
    required this.memberId,
    required String tripSecret,
    this.multiHop = false,
    MeshTransport? transport,
  })  : _key = sha256.convert(utf8.encode('convoy-mesh:$tripId:$tripSecret')).bytes,
        _transport = transport ?? PlatformMeshTransport();

  final String tripId;
  final String memberId;
  final List<int> _key;
  final MeshTransport _transport;

  /// Premium: forward frames for cars out of our direct range (TTL 4).
  /// Free: deliver only what we hear directly (TTL 1).
  final bool multiHop;

  static const int tagLength = 8;
  int _seq = 0;
  final _seen = <String>{};
  StreamSubscription<MeshEvent>? _sub;

  final _positions = StreamController<VehiclePosition>.broadcast();
  final _chat = StreamController<ChatMessage>.broadcast();
  final _waypoints = StreamController<Waypoint>.broadcast();
  int peers = 0;

  Stream<VehiclePosition> get positions => _positions.stream;
  Stream<ChatMessage> get chat => _chat.stream;
  Stream<Waypoint> get waypoints => _waypoints.stream;

  int get _ttl => multiHop ? 4 : 1;

  /// Short tag peers advertise; discovery ignores anyone with a different one.
  String get tripTag => tripId.replaceAll('-', '').substring(0, 12);

  Future<bool> start() async {
    if (!await _permissions()) return false;
    _sub = _transport.events.listen(_onEvent);
    await _transport.start(tripTag: tripTag, endpointName: '$tripTag|${memberId.substring(0, 8)}');
    return true;
  }

  Future<bool> _permissions() async {
    if (Platform.isAndroid) {
      final res = await [
        Permission.locationWhenInUse,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ].request();
      // Older Android versions report the BT-12 permissions as denied/
      // restricted; only location is mandatory there.
      return res[Permission.locationWhenInUse]?.isGranted ?? false;
    }
    if (Platform.isIOS) {
      final s = await Permission.bluetooth.request();
      return !s.isPermanentlyDenied;
    }
    return false;
  }

  // ───────────────────────────── outbound ─────────────────────────────

  Future<void> sendPosition(VehiclePosition p) async {
    final f = PositionFrame(position: p, ttl: _ttl, hops: 0, sequence: _nextSeq());
    _remember(f.dedupeKey);
    await _transport.broadcast(_sign(f.encode()), reliable: false);
  }

  Future<void> sendChat(ChatMessage m) => _sendData(MeshFrame.typeChat, m.toRow());

  Future<void> sendWaypoint(Waypoint w) => _sendData(MeshFrame.typeItinerary, w.toRow());

  Future<void> _sendData(int type, Map<String, dynamic> row) async {
    final f = DataFrame(type: type, originId: memberId, ttl: _ttl, hops: 0, sequence: _nextSeq(), json: jsonEncode(row));
    _remember(f.dedupeKey);
    await _transport.broadcast(_sign(f.encode()), reliable: true);
  }

  int _nextSeq() => _seq = (_seq + 1) & 0xFFFF;

  // ───────────────────────────── inbound ──────────────────────────────

  void _onEvent(MeshEvent e) {
    switch (e) {
      case MeshPeers(:final count):
        peers = count;
      case MeshPayload(:final bytes):
        handleIncoming(bytes);
    }
  }

  /// Verifies, de-duplicates, delivers and (premium) relays a frame.
  /// Public for tests.
  void handleIncoming(Uint8List signed) {
    final raw = _verify(signed);
    if (raw == null) return;
    switch (frameType(raw)) {
      case MeshFrame.typePosition:
        final f = PositionFrame.decode(raw);
        if (f == null || f.position.memberId == memberId || !_remember(f.dedupeKey)) return;
        _positions.add(f.position);
        final r = f.relayed();
        if (r != null) _transport.broadcast(_sign(r.encode()), reliable: false);
      case MeshFrame.typeChat || MeshFrame.typeItinerary:
        final f = DataFrame.decode(raw);
        if (f == null || f.originId == memberId || !_remember(f.dedupeKey)) return;
        try {
          final row = jsonDecode(f.json) as Map<String, dynamic>;
          if (row['trip_id'] != tripId) return;
          if (f.type == MeshFrame.typeChat) {
            _chat.add(ChatMessage.fromRow(row).copyWith(viaMesh: true));
          } else {
            _waypoints.add(Waypoint.fromRow(row));
          }
        } catch (_) {
          return;
        }
        final r = f.relayed();
        if (r != null) _transport.broadcast(_sign(r.encode()), reliable: true);
    }
  }

  /// Returns false if already seen. Bounded so a long trip doesn't leak.
  bool _remember(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    if (_seen.length > 4096) _seen.remove(_seen.first);
    return true;
  }

  // Relays re-sign after decrementing TTL; every member holds the key.
  Uint8List _sign(Uint8List frame) {
    final tag = Hmac(sha256, _key).convert(frame).bytes.sublist(0, tagLength);
    return Uint8List.fromList([...frame, ...tag]);
  }

  Uint8List? _verify(Uint8List signed) {
    if (signed.length <= tagLength) return null;
    final frame = Uint8List.sublistView(signed, 0, signed.length - tagLength);
    final tag = signed.sublist(signed.length - tagLength);
    final expect = Hmac(sha256, _key).convert(frame).bytes.sublist(0, tagLength);
    var diff = 0;
    for (var i = 0; i < tagLength; i++) {
      diff |= tag[i] ^ expect[i];
    }
    return diff == 0 ? Uint8List.fromList(frame) : null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _transport.stop();
    peers = 0;
  }

  Future<void> dispose() async {
    await stop();
    await _positions.close();
    await _chat.close();
    await _waypoints.close();
  }
}

// ──────────────────────────── transport ─────────────────────────────

sealed class MeshEvent {
  const MeshEvent();
}

class MeshPeers extends MeshEvent {
  const MeshPeers(this.count);
  final int count;
}

class MeshPayload extends MeshEvent {
  const MeshPayload(this.bytes);
  final Uint8List bytes;
}

abstract class MeshTransport {
  Stream<MeshEvent> get events;
  Future<void> start({required String tripTag, required String endpointName});
  Future<void> broadcast(Uint8List bytes, {required bool reliable});
  Future<void> stop();
}

/// Native Nearby Connections / MultipeerConnectivity.
class PlatformMeshTransport implements MeshTransport {
  static const _method = MethodChannel('convoy/mesh');
  static const _events = EventChannel('convoy/mesh/events');

  @override
  late final Stream<MeshEvent> events = _events.receiveBroadcastStream().map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    return switch (m['type']) {
      'peers' => MeshPeers((m['count'] as num).toInt()),
      _ => MeshPayload(m['bytes'] as Uint8List),
    };
  });

  @override
  Future<void> start({required String tripTag, required String endpointName}) =>
      _method.invokeMethod('start', {'tripTag': tripTag, 'endpointName': endpointName});

  @override
  Future<void> broadcast(Uint8List bytes, {required bool reliable}) =>
      _method.invokeMethod('broadcast', {'bytes': bytes, 'reliable': reliable});

  @override
  Future<void> stop() => _method.invokeMethod('stop');
}
