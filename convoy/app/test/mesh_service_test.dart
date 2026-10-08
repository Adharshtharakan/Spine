import 'dart:async';
import 'dart:typed_data';

import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/social.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/services/mesh/fragmenter.dart';
import 'package:convoy/services/mesh/frame_crypto.dart';
import 'package:convoy/services/mesh/mesh_service.dart';
import 'package:convoy/services/mesh/meshtastic_proto.dart';
import 'package:flutter_test/flutter_test.dart';

const _trip = '7cba5322-6ff2-40c6-9a10-5720dc911c3c';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _c = 'cccccccc-0000-4000-8000-000000000003';

/// In-memory link that records what a node transmits.
class FakeTransport implements MeshTransport {
  FakeTransport(this.id, {this.floods = false, this.maxPayload = 32000, Duration? interval})
      : positionInterval = interval ?? (floods ? const Duration(seconds: 30) : const Duration(seconds: 1));

  @override
  final String id;
  @override
  final bool floods;
  @override
  final int maxPayload;
  @override
  final Duration positionInterval;

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

MeshService _node(String member, List<MeshTransport> t, {String secret = 'INVITE42', bool premium = true}) =>
    MeshService(tripId: _trip, memberId: member, tripSecret: secret, multiHop: premium, transports: t);

final _t0 = DateTime.utc(2026, 10, 1, 12);

VehiclePosition _pos(String id, {DateTime? at, double lat = 12.9716, double heading = 45, double speed = 20}) =>
    VehiclePosition(memberId: id, point: GeoPoint(lat, 77.5946), timestamp: at ?? _t0, speedMps: speed, headingDeg: heading);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('encryption', () {
    test('only the same trip key opens a frame; tampering is detected', () async {
      final k1 = FrameCrypto(tripId: _trip, tripSecret: 'INVITE42');
      final k2 = FrameCrypto(tripId: _trip, tripSecret: 'OTHER');
      final sealed = await k1.seal(Uint8List.fromList([1, 2, 3, 4]));
      expect(sealed.length, 4 + FrameCrypto.overhead);
      expect(await k1.open(sealed), [1, 2, 3, 4]);
      expect(await k2.open(sealed), isNull);
      sealed[20] ^= 1;
      expect(await k1.open(sealed), isNull);
    });
  });

  group('fragmenter', () {
    test('splits to the MTU and reassembles in any order', () {
      final f = Fragmenter();
      final data = Uint8List.fromList(List.generate(700, (i) => i & 0xFF));
      final parts = f.split(data, 200);
      expect(parts.every((p) => p.length <= 200), isTrue);
      final rx = Fragmenter();
      Uint8List? out;
      for (final p in parts.reversed) {
        out = rx.accept('n1', p) ?? out;
      }
      expect(out, data);
    });

    test('small payloads pass straight through', () {
      final d = Uint8List.fromList([9, 9, 9]);
      expect(Fragmenter().split(d, 200).single, d);
      expect(Fragmenter().accept('x', d), d);
    });
  });

  group('Meshtastic protocol', () {
    test('ToRadio packet carries our payload on PRIVATE_APP to broadcast', () {
      final bytes = Meshtastic.toRadioPacket(Uint8List.fromList([0xC5, 1, 2]), packetId: 77, hopLimit: 3);
      // ToRadio.packet (field 1, length-delimited)
      expect(bytes[0], (1 << 3) | 2);
      // Payload and portnum 256 (varint 0x80 0x02) are present.
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, contains('c50102'));
      expect(hex, contains('088002'));
      // to = 0xFFFFFFFF as fixed32 (field 2, wire type 5).
      expect(hex, contains('15ffffffff'));
    });

    test('decodes a FromRadio packet built the way the firmware does', () {
      // FromRadio{ id:1, packet:{ from:0x0A0B0C0D, to:bcast, decoded:{portnum:256, payload:[0xC5,7]}, rx_rssi:-90, hop_limit:2, hop_start:3 } }
      final data = [0x08, 0x80, 0x02, 0x12, 0x02, 0xC5, 0x07];
      final rssi = [0x60, 0xA6, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]; // field 12 varint -90
      final packet = [
        0x0D, 0x0D, 0x0C, 0x0B, 0x0A, // from fixed32
        0x15, 0xFF, 0xFF, 0xFF, 0xFF, // to
        0x22, data.length, ...data, // decoded
        ...rssi,
        0x48, 0x02, // hop_limit
        0x78, 0x03, // hop_start
      ];
      final from = Uint8List.fromList([0x08, 0x01, 0x12, packet.length, ...packet]);
      final msg = Meshtastic.decodeFromRadio(from);
      expect(msg.packet!.from, 0x0A0B0C0D);
      expect(msg.packet!.portnum, Meshtastic.privateAppPort);
      expect(msg.packet!.payload, [0xC5, 0x07]);
      expect(msg.packet!.rssi, -90);
      expect(msg.packet!.hops, 1);
    });

    test('decodes config-complete and my_info', () {
      final m = Meshtastic.decodeFromRadio(Uint8List.fromList([0x1A, 0x02, 0x08, 0x2A, 0x38, 0x05]));
      expect(m.myNodeNum, 42);
      expect(m.configCompleteId, 5);
      expect(m.packet, isNull);
    });

    test('garbage never throws', () {
      expect(() => Meshtastic.decodeFromRadio(Uint8List.fromList([0xFF, 0xFF, 0xFF])), returnsNormally);
    });
  });

  group('MeshService', () {
    test('members exchange positions over the radio; strangers cannot read them', () async {
      final ra = FakeTransport('lora', floods: true, maxPayload: 200);
      final a = _node(_a, [ra]);
      final b = _node(_b, [FakeTransport('lora', floods: true, maxPayload: 200)]);
      final stranger = _node(_c, [FakeTransport('lora', floods: true)], secret: 'OTHER');

      final got = <VehiclePosition>[], strangerGot = <VehiclePosition>[];
      b.positions.listen(got.add);
      stranger.positions.listen(strangerGot.add);

      await a.sendPosition(_pos(_a));
      expect(ra.sent.single.length, lessThanOrEqualTo(200));
      await b.handleIncoming(ra.sent.single, transport: 'lora', source: 'n1');
      await stranger.handleIncoming(ra.sent.single, transport: 'lora', source: 'n1');
      await _settle();
      expect(got.single.memberId, _a);
      expect(got.single.source, PositionSource.mesh);
      expect(strangerGot, isEmpty);
    });

    test('radio positions are rate-limited but urgent changes go out at once', () {
      final lora = FakeTransport('lora', floods: true);
      final m = _node(_a, [lora]);
      expect(m.isDue(lora, _pos(_a)), isTrue);
      // Simulate a send, then check follow-ups.
      m.sendPosition(_pos(_a));
      expect(m.isDue(lora, _pos(_a, at: _t0.add(const Duration(seconds: 15)))), isFalse, reason: 'cruising, no change');
      expect(m.isDue(lora, _pos(_a, at: _t0.add(const Duration(seconds: 15)), speed: 0)), isTrue, reason: 'stopped');
      expect(m.isDue(lora, _pos(_a, at: _t0.add(const Duration(seconds: 15)), heading: 140)), isTrue, reason: 'turned');
      expect(m.isDue(lora, _pos(_a, at: _t0.add(const Duration(seconds: 31)))), isTrue, reason: 'interval');
    });

    test('long chat messages are fragmented for LoRa and reassembled', () async {
      final ra = FakeTransport('lora', floods: true, maxPayload: 200);
      final a = _node(_a, [ra]);
      final b = _node(_b, [FakeTransport('lora', floods: true, maxPayload: 200)]);
      final msgs = <ChatMessage>[];
      b.chat.listen(msgs.add);
      await a.sendChat(ChatMessage(
        id: 'dddddddd-0000-4000-8000-000000000009',
        tripId: _trip,
        senderId: _a,
        body: 'Road closed after the bridge, take the left fork at the temple and wait at the tea stall. ' * 3,
        createdAt: _t0,
      ));
      expect(ra.sent.length, greaterThan(1));
      for (final p in ra.sent) {
        await b.handleIncoming(p, transport: 'lora', source: 'a');
      }
      await _settle();
      expect(msgs.single.body, startsWith('Road closed'));
      expect(msgs.single.viaMesh, isTrue);
    });

    test('premium bridges radio to the phone mesh but never radio to radio', () async {
      final ra = FakeTransport('lora', floods: true);
      final a = _node(_a, [ra]);
      final bLora = FakeTransport('lora', floods: true), bNearby = FakeTransport('nearby');
      final b = _node(_b, [bLora, bNearby]);
      await a.sendPosition(_pos(_a));
      await b.handleIncoming(ra.sent.single, transport: 'lora', source: 'a');
      await b.handleIncoming(ra.sent.single, transport: 'lora', source: 'a'); // duplicate
      expect(bLora.sent, isEmpty);
      expect(bNearby.sent, hasLength(1));
    });

    test('free tier delivers but does not bridge', () async {
      final ra = FakeTransport('lora', floods: true);
      final a = _node(_a, [ra], premium: false);
      final bNearby = FakeTransport('nearby');
      final b = _node(_b, [FakeTransport('lora', floods: true), bNearby], premium: false);
      await a.sendPosition(_pos(_a));
      await b.handleIncoming(ra.sent.single, transport: 'lora', source: 'a');
      expect(bNearby.sent, isEmpty);
    });

    test('gateway pushes cloud positions to the radio, once a minute, only for cars not on the radio', () async {
      final gwLora = FakeTransport('lora', floods: true);
      final gw = _node(_a, [gwLora]);
      await gw.forwardFromCloud(_pos(_b), now: _t0);
      await gw.forwardFromCloud(_pos(_b, at: _t0.add(const Duration(seconds: 5))), now: _t0.add(const Duration(seconds: 5)));
      expect(gwLora.sent, hasLength(1));

      // C is heard on the radio directly, so the gateway leaves it alone.
      final cLora = FakeTransport('lora', floods: true);
      final c = _node(_c, [cLora]);
      await c.sendPosition(_pos(_c));
      await gw.handleIncoming(cLora.sent.single, transport: 'lora', source: 'c');
      await gw.forwardFromCloud(_pos(_c, at: _t0.add(const Duration(seconds: 2))));
      expect(gwLora.sent, hasLength(1));
    });

    test('the same fix from its car and from a gateway is delivered once', () async {
      final aLora = FakeTransport('lora', floods: true);
      final a = _node(_a, [aLora]);
      final gwLora = FakeTransport('lora', floods: true);
      final gw = _node(_c, [gwLora]);
      final b = _node(_b, [FakeTransport('lora', floods: true)]);
      final got = <VehiclePosition>[];
      b.positions.listen(got.add);
      await a.sendPosition(_pos(_a));
      await gw.forwardFromCloud(_pos(_a));
      await b.handleIncoming(aLora.sent.single, transport: 'lora', source: 'a');
      await b.handleIncoming(gwLora.sent.single, transport: 'lora', source: 'gw');
      await _settle();
      expect(got, hasLength(1));
    });
  });
}
