import 'dart:typed_data';

import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/services/mesh/position_frame.dart';
import 'package:convoy/services/tracking/dead_reckoning.dart';
import 'package:convoy/services/tracking/lead_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

const _lead = '11111111-1111-4111-8111-111111111111';
const _mid = '22222222-2222-4222-8222-222222222222';
const _tail = '33333333-3333-4333-8333-333333333333';

// A straight road heading east along the equator, ~111 km per degree.
const _route = [GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(0, 2)];

VehiclePosition _at(String id, double lng, DateTime t, {double speed = 25}) =>
    VehiclePosition(memberId: id, point: GeoPoint(0.001, lng), timestamp: t, speedMps: speed, headingDeg: 90);

void main() {
  final now = DateTime.utc(2026, 10, 1, 12);

  group('Geo', () {
    test('distance and bearing', () {
      final d = Geo.distanceMeters(const GeoPoint(0, 0), const GeoPoint(0, 1));
      expect(d, closeTo(111195, 50));
      expect(Geo.bearingDeg(const GeoPoint(0, 0), const GeoPoint(0, 1)), closeTo(90, 0.01));
    });

    test('route projection measures progress', () {
      final p = Geo.projectOntoRoute(_route, const GeoPoint(0.01, 1.5));
      expect(p.alongMeters, closeTo(111195 * 1.5, 200));
      expect(p.offRouteMeters, closeTo(1112, 20));
    });

    test('corridor boxes cover every route point', () {
      final boxes = Geo.corridorBoxes(_route, maxSpanM: 50000);
      expect(boxes.length, greaterThan(1));
      for (final p in _route) {
        expect(boxes.any((b) => b.contains(p)), isTrue);
      }
    });
  });

  group('LeadVehicleResolver', () {
    const resolver = LeadVehicleResolver();
    final positions = {
      _lead: _at(_lead, 1.2, now),
      _mid: _at(_mid, 0.9, now),
      _tail: _at(_tail, 0.3, now),
    };

    test('honours the designated lead while it reports', () {
      final r = resolver.resolve(designatedMemberId: _mid, positions: positions, route: _route, now: now)!;
      expect(r.memberId, _mid);
      expect(r.reason, LeadReason.designated);
    });

    test('falls back to the vehicle furthest along when the lead goes silent', () {
      final silent = {...positions, _mid: _at(_mid, 0.9, now.subtract(const Duration(minutes: 5)))};
      final r = resolver.resolve(designatedMemberId: _mid, positions: silent, route: _route, now: now)!;
      expect(r.memberId, _lead);
      expect(r.reason, LeadReason.furthestAlongRoute);
    });

    test('standings are ordered front to back with gaps to the lead', () {
      final lead = resolver.resolve(designatedMemberId: null, positions: positions, route: _route, now: now);
      final s = resolver.standings(lead: lead, positions: positions, route: _route, now: now);
      expect(s.map((x) => x.memberId), [_lead, _mid, _tail]);
      expect(s.last.gapToLeadMeters, closeTo(111195 * 0.9, 300));
    });
  });

  group('DeadReckoning', () {
    test('projects a silent vehicle along the route with growing uncertainty', () {
      final last = _at(_tail, 0.5, now.subtract(const Duration(minutes: 2)));
      final est = const DeadReckoning().estimate(last, _route, now);
      expect(est.source, PositionSource.estimated);
      final moved = Geo.distanceMeters(last.point, est.point);
      expect(moved, closeTo(25 * 120, 100));
      expect(est.accuracyM, greaterThan(last.accuracyM + 600));
    });
  });

  group('Mesh frames', () {
    test('position frame round-trips in 40 bytes', () {
      final pos = VehiclePosition(
        memberId: _lead,
        point: const GeoPoint(-33.8688197, 151.2092955),
        timestamp: DateTime.utc(2026, 10, 1, 12, 0, 5),
        speedMps: 27.78,
        headingDeg: 271.5,
        accuracyM: 6,
      );
      final bytes = PositionFrame(position: pos, ttl: 3, hops: 0, sequence: 77).encode();
      expect(bytes.length, 40);
      final back = PositionFrame.decode(bytes)!;
      expect(back.position.memberId, _lead);
      expect(back.position.point.lat, closeTo(pos.point.lat, 1e-6));
      expect(back.position.point.lng, closeTo(pos.point.lng, 1e-6));
      expect(back.position.timestamp, pos.timestamp);
      expect(back.position.speedMps, closeTo(27.78, 0.01));
      expect(back.position.headingDeg, closeTo(271.5, 0.01));
      expect(back.sequence, 77);
      expect(back.position.source, PositionSource.mesh);
    });

    test('relay decrements ttl and stops at zero', () {
      final f = PositionFrame(position: _at(_lead, 1, now), ttl: 2, hops: 0, sequence: 1);
      final r1 = f.relayed()!;
      expect(r1.ttl, 1);
      expect(r1.hops, 1);
      expect(r1.relayed(), isNull);
    });

    test('data frames carry JSON and are not mistaken for positions', () {
      final f = DataFrame(
          type: MeshFrame.typeChat, originId: _mid, ttl: 4, hops: 0, sequence: 9, json: '{"body":"Fuel stop ahead"}');
      final bytes = f.encode();
      expect(PositionFrame.decode(bytes), isNull);
      expect(frameType(bytes), MeshFrame.typeChat);
      final back = DataFrame.decode(bytes)!;
      expect(back.json, contains('Fuel stop'));
      expect(back.originId, _mid);
      expect(DataFrame.decode(Uint8List(3)), isNull);
    });
  });
}
