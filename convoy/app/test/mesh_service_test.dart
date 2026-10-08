import 'dart:async';
import 'dart:typed_data';

import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/social.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/services/mesh/mesh_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _trip = '7cba5322-6ff2-40c6-9a10-5720dc911c3c';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _c = 'cccccccc-0000-4000-8000-000000000003';

/// In-memory radio: records what each node broadcasts.
class FakeTransport implements MeshTransport {
  final sent = <Uint8List>[];
  final _events = StreamController<MeshEvent>.broadcast();

  @override
  Stream<MeshEvent> get events => _events.stream;

  @override
  Future<void> broadcast(Uint8List bytes, {required bool reliable}) async => sent.add(bytes);

  @override
  Future<void> start({required String tripTag, required String endpointName}) async {}

  @override
  Future<void> stop() async {}
}

MeshService _node(String member, FakeTransport t, {String secret = 'INVITE42', bool multiHop = true}) =>
    MeshService(tripId: _trip, memberId: member, tripSecret: secret, multiHop: multiHop, transport: t);

VehiclePosition _pos(String id) => VehiclePosition(
      memberId: id,
      point: const GeoPoint(12.9716, 77.5946),
      timestamp: DateTime.utc(2026, 10, 1, 12),
      speedMps: 20,
      headingDeg: 45,
    );

void main() {
  test('members exchange positions; strangers with another secret are ignored', () async {
    final ta = FakeTransport(), tb = FakeTransport(), tx = FakeTransport();
    final a = _node(_a, ta);
    final b = _node(_b, tb);
    final stranger = _node(_c, tx, secret: 'OTHER');

    await a.sendPosition(_pos(_a));
    final got = <VehiclePosition>[];
    b.positions.listen(got.add);
    final strangerGot = <VehiclePosition>[];
    stranger.positions.listen(strangerGot.add);

    b.handleIncoming(ta.sent.single);
    stranger.handleIncoming(ta.sent.single);
    await Future<void>.delayed(Duration.zero);

    expect(got.single.memberId, _a);
    expect(got.single.source, PositionSource.mesh);
    expect(strangerGot, isEmpty);
  });

  test('tampered frames are rejected', () async {
    final ta = FakeTransport(), tb = FakeTransport();
    final a = _node(_a, ta);
    final b = _node(_b, tb);
    await a.sendPosition(_pos(_a));
    final bytes = Uint8List.fromList(ta.sent.single);
    bytes[22] ^= 0xFF; // nudge the latitude
    final got = <VehiclePosition>[];
    b.positions.listen(got.add);
    b.handleIncoming(bytes);
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty);
  });

  test('premium nodes relay once, with TTL decremented; duplicates are dropped', () async {
    final ta = FakeTransport(), tb = FakeTransport();
    final a = _node(_a, ta);
    final b = _node(_b, tb);
    await a.sendPosition(_pos(_a));
    b.handleIncoming(ta.sent.single);
    b.handleIncoming(ta.sent.single);
    expect(tb.sent, hasLength(1), reason: 'relayed exactly once');
    expect(tb.sent.single[2], 3, reason: 'ttl 4 -> 3');
    expect(tb.sent.single[3], 1, reason: 'one hop');
  });

  test('free tier does not relay', () async {
    final ta = FakeTransport(), tb = FakeTransport();
    final a = _node(_a, ta, multiHop: false);
    final b = _node(_b, tb, multiHop: false);
    await a.sendPosition(_pos(_a));
    b.handleIncoming(ta.sent.single);
    expect(tb.sent, isEmpty);
  });

  test('chat crosses the mesh and is marked as such', () async {
    final ta = FakeTransport(), tb = FakeTransport();
    final a = _node(_a, ta);
    final b = _node(_b, tb);
    final msgs = <ChatMessage>[];
    b.chat.listen(msgs.add);
    await a.sendChat(ChatMessage(
      id: 'dddddddd-0000-4000-8000-000000000009',
      tripId: _trip,
      senderId: _a,
      body: 'Fuel in 10 km',
      createdAt: DateTime.utc(2026, 10, 1, 12),
    ));
    b.handleIncoming(ta.sent.single);
    await Future<void>.delayed(Duration.zero);
    expect(msgs.single.body, 'Fuel in 10 km');
    expect(msgs.single.viaMesh, isTrue);
  });
}
