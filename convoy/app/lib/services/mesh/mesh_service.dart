import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/geo/geo.dart';
import '../../data/models/social.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';
import 'fragmenter.dart';
import 'frame_crypto.dart';
import 'position_frame.dart';

/// Off-grid convoy link: everything that is not the cloud.
///
/// Runs any number of [MeshTransport]s side by side:
/// * `lora`   — a Meshtastic LoRa radio per car: kilometres of range, and
///              the radios relay for each other. The real answer when the
///              convoy is strung out with no cell signal.
/// * `nearby` — phone-to-phone Bluetooth / Wi-Fi Direct: tens to a few
///              hundred metres, useful only when cars are bunched up.
///
/// Every frame is encrypted and authenticated with the trip key
/// ([FrameCrypto]), fragmented to fit the link, rate-limited per link, and
/// de-duplicated on receipt. With [multiHop] (Premium) frames heard on one
/// link are bridged onto the others, and a car that still has signal acts as
/// a gateway, pushing the cloud's positions and chat onto the radio for the
/// cars that have none ([forwardFromCloud], [forwardChatFromCloud]).
class MeshService {
  MeshService({
    required this.tripId,
    required this.memberId,
    required String tripSecret,
    this.multiHop = false,
    List<MeshTransport>? transports,
  })  : _crypto = FrameCrypto(tripId: tripId, tripSecret: tripSecret),
        transports = transports ?? [PlatformMeshTransport()];

  final String tripId;
  final String memberId;
  final bool multiHop;
  final List<MeshTransport> transports;
  final FrameCrypto _crypto;
  final _fragmenter = Fragmenter();

  int _seq = 0;
  final _seen = <String>{};
  final List<StreamSubscription<MeshEvent>> _subs = [];

  final _positions = StreamController<VehiclePosition>.broadcast();
  final _chat = StreamController<ChatMessage>.broadcast();
  final _waypoints = StreamController<Waypoint>.broadcast();
  final Map<String, int> _peers = {};

  Stream<VehiclePosition> get positions => _positions.stream;
  Stream<ChatMessage> get chat => _chat.stream;
  Stream<Waypoint> get waypoints => _waypoints.stream;

  int get peers => _peers.values.fold(0, (a, b) => a + b);
  int peersOn(String transport) => _peers[transport] ?? 0;
  bool get hasRadio => transports.any((t) => t.floods);

  int get _ttl => multiHop ? 4 : 1;

  /// Last position we sent on each link, for rate limiting.
  final Map<String, VehiclePosition> _lastSent = {};

  /// memberId → when last heard over a radio link / last bridged onto it.
  final Map<String, DateTime> _heardOnRadio = {};
  final Map<String, DateTime> _bridgedAt = {};

  String get tripTag => tripId.replaceAll('-', '').substring(0, 12);

  Future<bool> start() async {
    if (!await _permissions()) return false;
    for (final t in transports) {
      _subs.add(t.events.listen(_onEvent));
      await t.start(tripTag: tripTag, endpointName: '$tripTag|${memberId.substring(0, 8)}');
    }
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
      // Older Android versions report the Android 12+ Bluetooth permissions
      // as denied; only location is mandatory there.
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
    final frame = PositionFrame(position: p, ttl: _ttl, hops: 0, sequence: _nextSeq());
    _remember(frame.dedupeKey);
    for (final tr in transports) {
      if (!isDue(tr, p)) continue;
      _lastSent[tr.id] = p;
      await _send(tr, frame.encode(), reliable: false);
    }
  }

  /// A position goes out when the link's interval has passed — or, on slow
  /// radio links, sooner when the car turned, moved far, or stopped/started,
  /// which is exactly when the others need to know. Public for tests.
  bool isDue(MeshTransport tr, VehiclePosition p) {
    final last = _lastSent[tr.id];
    if (last == null) return true;
    final elapsed = p.timestamp.difference(last.timestamp);
    if (elapsed >= tr.positionInterval) return true;
    if (!tr.floods || elapsed < const Duration(seconds: 10)) return false;
    final moved = Geo.distanceMeters(last.point, p.point);
    final turn = ((p.headingDeg - last.headingDeg + 540) % 360 - 180).abs();
    final stopChange = (last.speedMps > 2) != (p.speedMps > 2);
    return moved > 500 || (turn > 45 && p.speedMps > 2) || stopChange;
  }

  Future<void> sendChat(ChatMessage m) => _sendData(MeshFrame.typeChat, m.toRow());

  Future<void> sendWaypoint(Waypoint w) => _sendData(MeshFrame.typeItinerary, _compact(w.toRow()));

  Future<void> _sendData(int type, Map<String, dynamic> row, {Iterable<MeshTransport>? only}) async {
    final f = DataFrame(type: type, originId: memberId, ttl: _ttl, hops: 0, sequence: _nextSeq(), json: jsonEncode(row));
    _remember(_dataKey(type, row));
    for (final tr in only ?? transports) {
      await _send(tr, f.encode(), reliable: true);
    }
  }

  /// Gateway duty: push the cloud's position for another car onto the
  /// radio, for cars that have no signal. Skipped for members already heard
  /// on the radio in the last minute (everyone in range has them), and at
  /// most once a minute per member to protect LoRa airtime.
  Future<void> forwardFromCloud(VehiclePosition p, {DateTime? now}) async {
    if (!multiHop || p.memberId == memberId) return;
    final radios = transports.where((x) => x.floods).toList();
    if (radios.isEmpty) return;
    final t = now ?? DateTime.now();
    final heard = _heardOnRadio[p.memberId];
    final bridged = _bridgedAt[p.memberId];
    if (heard != null && t.difference(heard) < const Duration(minutes: 1)) return;
    if (bridged != null && t.difference(bridged) < const Duration(minutes: 1)) return;
    final frame = PositionFrame(position: p, ttl: 1, hops: 1, sequence: _nextSeq());
    if (!_remember(frame.dedupeKey)) return;
    _bridgedAt[p.memberId] = t;
    for (final r in radios) {
      await _send(r, frame.encode(), reliable: false);
    }
  }

  /// Gateway duty for chat: messages from the cloud reach radio-only cars.
  Future<void> forwardChatFromCloud(ChatMessage m) async {
    if (!multiHop || m.senderId == memberId) return;
    final row = m.toRow();
    if (_seen.contains(_dataKey(MeshFrame.typeChat, row))) return;
    await _sendData(MeshFrame.typeChat, row, only: transports.where((t) => t.floods));
  }

  Future<void> _send(MeshTransport tr, List<int> plain, {required bool reliable}) async {
    final sealed = await _crypto.seal(Uint8List.fromList(plain));
    for (final part in _fragmenter.split(sealed, tr.maxPayload)) {
      await tr.broadcast(part, reliable: reliable);
    }
  }

  int _nextSeq() => _seq = (_seq + 1) & 0xFFFF;

  /// Drops nulls and empty strings: LoRa bytes are precious.
  static Map<String, dynamic> _compact(Map<String, dynamic> row) =>
      {for (final e in row.entries) if (e.value != null && e.value != '') e.key: e.value};

  /// Content identity, so the same message arriving from its author and
  /// from a gateway is only delivered once.
  static String _dataKey(int type, Map<String, dynamic> row) =>
      type == MeshFrame.typeChat ? 'chat:${row['id']}' : 'wp:${row['id']}:${row['hlc']}';

  // ───────────────────────────── inbound ──────────────────────────────

  void _onEvent(MeshEvent e) {
    switch (e) {
      case MeshPeers(:final count, :final transport):
        _peers[transport] = count;
      case MeshPayload(:final bytes, :final transport, :final source):
        handleIncoming(bytes, transport: transport, source: source);
    }
  }

  /// Reassembles, decrypts, de-duplicates, delivers and bridges a frame.
  /// Public for tests.
  Future<void> handleIncoming(Uint8List packet, {String transport = 'nearby', String source = 'peer'}) async {
    final whole = _fragmenter.accept('$transport/$source', packet);
    if (whole == null) return;
    final raw = await _crypto.open(whole);
    if (raw == null) return; // another trip, a stranger, or tampered with
    final from = transports.where((t) => t.id == transport).firstOrNull;
    final fromRadio = from?.floods ?? false;

    switch (frameType(raw)) {
      case MeshFrame.typePosition:
        final f = PositionFrame.decode(raw);
        if (f == null || f.position.memberId == memberId) return;
        if (fromRadio) _heardOnRadio[f.position.memberId] = DateTime.now();
        if (!_remember(f.dedupeKey)) return;
        _positions.add(f.position);
        final r = f.relayed();
        if (r != null) await _bridge(r.encode(), from, reliable: false);
      case MeshFrame.typeChat || MeshFrame.typeItinerary:
        final f = DataFrame.decode(raw);
        if (f == null) return;
        final Map<String, dynamic> row;
        try {
          row = jsonDecode(f.json) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        if (row['trip_id'] != tripId || !_remember(_dataKey(f.type, row))) return;
        try {
          if (f.type == MeshFrame.typeChat) {
            _chat.add(ChatMessage.fromRow(row).copyWith(viaMesh: true));
          } else {
            _waypoints.add(Waypoint.fromRow(row));
          }
        } catch (_) {
          return;
        }
        final r = f.relayed();
        if (r != null) await _bridge(r.encode(), from, reliable: true);
    }
  }

  /// Forwards to the other links. Never radio→radio (the radios flood by
  /// themselves); phone-mesh→phone-mesh only within the TTL.
  Future<void> _bridge(List<int> frame, MeshTransport? from, {required bool reliable}) async {
    for (final t in transports) {
      if (from != null && t.floods && from.floods) continue;
      await _send(t, frame, reliable: reliable);
    }
  }

  /// Returns false if already seen. Bounded so a long trip doesn't leak.
  bool _remember(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    if (_seen.length > 8192) _seen.remove(_seen.first);
    return true;
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final t in transports) {
      await t.stop();
    }
    _peers.clear();
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
  const MeshPeers(this.count, {this.transport = 'nearby'});
  final int count;
  final String transport;
}

class MeshPayload extends MeshEvent {
  const MeshPayload(this.bytes, {this.transport = 'nearby', this.source = 'peer'});
  final Uint8List bytes;
  final String transport;

  /// Sender identity on that link, for fragment reassembly.
  final String source;
}

abstract class MeshTransport {
  String get id;

  /// Largest packet the link carries; bigger frames are fragmented.
  int get maxPayload;

  /// Baseline spacing between our own position broadcasts on this link.
  Duration get positionInterval;

  /// True when the link floods packets across nodes by itself (LoRa mesh).
  bool get floods;

  Stream<MeshEvent> get events;
  Future<void> start({required String tripTag, required String endpointName});
  Future<void> broadcast(Uint8List bytes, {required bool reliable});
  Future<void> stop();
}

/// Phone-to-phone: Nearby Connections (Android) / MultipeerConnectivity
/// (iOS). Short range — useful when cars are close together.
class PlatformMeshTransport implements MeshTransport {
  static const _method = MethodChannel('convoy/mesh');
  static const _events = EventChannel('convoy/mesh/events');

  @override
  String get id => 'nearby';
  @override
  int get maxPayload => 32 * 1024;
  @override
  Duration get positionInterval => const Duration(seconds: 1);
  @override
  bool get floods => false;

  @override
  late final Stream<MeshEvent> events = _events.receiveBroadcastStream().map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    return switch (m['type']) {
      'peers' => MeshPeers((m['count'] as num).toInt(), transport: id),
      _ => MeshPayload(m['bytes'] as Uint8List, transport: id, source: 'nearby'),
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
