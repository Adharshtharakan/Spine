import 'dart:typed_data';

import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/services/mesh/position_frame.dart';
import 'package:convoy/data/models/waypoint.dart';
import 'package:convoy/services/tracking/predictor.dart';
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

  group('ConvoyPredictor', () {
    const predictor = ConvoyPredictor();

    // A car's track: 25 m/s east along the equator for 3 minutes.
    List<VehiclePosition> track(String id, double startLng, DateTime end, {double speed = 25}) => [
          for (var s = 180; s >= 0; s -= 10)
            VehiclePosition(
              memberId: id,
              point: GeoPoint(0, startLng - speed * s / 111195),
              timestamp: end.subtract(Duration(seconds: s)),
              speedMps: speed,
              headingDeg: 90,
            ),
        ];

    test('follows the road at the smoothed recent speed', () {
      final lastAt = now.subtract(const Duration(minutes: 2));
      final h = track(_tail, 0.5, lastAt);
      final est = predictor.predict(
          last: h.last, route: _route, history: {_tail: h}, latest: {_tail: h.last}, stops: const [], now: now);
      expect(est.source, PositionSource.estimated);
      expect(Geo.distanceMeters(h.last.point, est.point), closeTo(25 * 120, 150));
      expect(est.point.lat, closeTo(0, 1e-6), reason: 'stays on the road');
      expect(est.basis, contains('along the road'));
      expect(est.accuracyM, greaterThan(h.last.accuracyM + 400));
    });

    test('holds a car at a planned stop until its departure time', () {
      final lastAt = now.subtract(const Duration(minutes: 20));
      final h = track(_tail, 0.5, lastAt);
      // A rest stop ~5.5 km ahead, leaving 30 min after the car went quiet.
      final stop = Waypoint(
        id: 'w',
        tripId: 't',
        name: 'Dhaba',
        location: const GeoPoint(0, 0.55),
        kind: WaypointKind.restStop,
        sortKey: 1,
        hlc: 'x',
        plannedDeparture: lastAt.add(const Duration(minutes: 30)),
      );
      final est = predictor.predict(
          last: h.last, route: _route, history: {_tail: h}, latest: {_tail: h.last}, stops: [stop], now: now);
      expect(Geo.distanceMeters(est.point, stop.location), lessThan(50));
      expect(est.basis, contains('Dhaba'));
    });

    test('keeps the gap to a convoy-mate that is still reporting', () {
      final lastAt = now.subtract(const Duration(minutes: 5));
      // Silent car was 1 km behind the lead when it went quiet.
      final silent = track(_tail, 0.5, lastAt);
      final leadThen = VehiclePosition(
          memberId: _lead, point: const GeoPoint(0, 0.5 + 1000 / 111195), timestamp: lastAt, speedMps: 10, headingDeg: 90);
      // The lead slowed to a crawl (traffic): only 600 m further now.
      final leadNow = VehiclePosition(
          memberId: _lead,
          point: GeoPoint(0, 0.5 + 1600 / 111195),
          timestamp: now.subtract(const Duration(seconds: 5)),
          speedMps: 2,
          headingDeg: 90);
      final est = predictor.predict(
        last: silent.last,
        route: _route,
        history: {_tail: silent, _lead: [leadThen, leadNow]},
        latest: {_tail: silent.last, _lead: leadNow},
        stops: const [],
        now: now,
        labels: const {_lead: 'Blue Jeep'},
      );
      // A speed-only model would put it 7.5 km on; the convoy model keeps
      // it ~1 km behind the lead.
      expect(Geo.distanceMeters(est.point, leadNow.point), closeTo(1000, 100));
      expect(est.basis, 'moving with Blue Jeep');
    });

    test('a car that had stopped stays put', () {
      final lastAt = now.subtract(const Duration(minutes: 3));
      final h = track(_tail, 0.5, lastAt);
      final stopped = VehiclePosition(memberId: _tail, point: h.last.point, timestamp: lastAt, speedMps: 0);
      final est = predictor.predict(
          last: stopped, route: _route, history: {_tail: [...h, stopped]}, latest: {_tail: stopped}, stops: const [], now: now);
      expect(Geo.distanceMeters(est.point, stopped.point), lessThan(1));
      expect(est.basis, contains('stopped'));
    });

    test('off the route it only extrapolates a few minutes', () {
      final lastAt = now.subtract(const Duration(minutes: 20));
      final off = VehiclePosition(
          memberId: _tail, point: const GeoPoint(0.5, 0.5), timestamp: lastAt, speedMps: 20, headingDeg: 0);
      final est = predictor.predict(last: off, route: _route, history: const {}, latest: {_tail: off}, stops: const [], now: now);
      expect(Geo.distanceMeters(off.point, est.point), closeTo(20 * 300, 50));
    });

    test('typical speed smooths over a single odd reading', () {
      final h = track(_tail, 0.5, now);
      final odd = VehiclePosition(memberId: _tail, point: h.last.point, timestamp: now, speedMps: 5, headingDeg: 90);
      expect(ConvoyPredictor.typicalSpeed([...h.sublist(0, h.length - 1), odd], odd), closeTo(0.7 * 25 + 0.3 * 5, 2));
    });
  });

  group('last-resort prediction inputs', () {
    final predictor = const ConvoyPredictor();

    test('with no recent history it uses the car\'s trip average, capped by the road', () {
      final last = VehiclePosition(
          memberId: _tail, point: const GeoPoint(0, 0.5), timestamp: now.subtract(const Duration(minutes: 10)), speedMps: 30, headingDeg: 90);
      final est = predictor.predict(
          last: last, route: _route, history: const {}, latest: {_tail: last}, stops: const [], now: now,
          averageSpeed: 20, roadSpeedAt: (_) => 25);
      expect(Geo.distanceMeters(last.point, est.point), closeTo(20 * 600, 200));
      expect(est.basis, contains('its average speed'));
    });

    test('with no history at all it uses the cached road speed over one odd reading', () {
      final last = VehiclePosition(
          memberId: _tail, point: const GeoPoint(0, 0.5), timestamp: now.subtract(const Duration(minutes: 10)), speedMps: 40, headingDeg: 90);
      final est = predictor.predict(
          last: last, route: _route, history: const {}, latest: {_tail: last}, stops: const [], now: now,
          roadSpeedAt: (_) => 20);
      expect(Geo.distanceMeters(last.point, est.point), closeTo(20 * 600, 200));
      expect(est.basis, contains('typical road speed'));
    });

    test('a coarse cell-tower fix starts with a wide uncertainty', () {
      final cell = VehiclePosition(
          memberId: _tail, point: const GeoPoint(0, 0.5), timestamp: now.subtract(const Duration(minutes: 1)),
          speedMps: 20, headingDeg: 90, accuracyM: 1500);
      final est = predictor.predict(last: cell, route: _route, history: const {}, latest: {_tail: cell}, stops: const [], now: now);
      expect(est.accuracyM, greaterThan(1500));
    });

    test('average speed ignores stops and GPS jumps', () {
      final avg = AverageSpeed();
      var t = now;
      var lng = 0.0;
      for (final v in [25.0, 25.0, 0.0, 0.0, 25.0, 500.0, 25.0]) {
        t = t.add(const Duration(seconds: 60));
        lng += v * 60 / 111195;
        avg.add(VehiclePosition(memberId: _tail, point: GeoPoint(0, lng), timestamp: t));
      }
      expect(avg.value, closeTo(25, 1));
    });

    test('road speeds come from the cached route legs', () {
      final r = RoadSpeeds.fromLegs([(distanceM: 10000, durationS: 400), (distanceM: 5000, durationS: 500)]);
      expect(r.at(3000), 25);
      expect(r.at(12000), 10);
      expect(RoadSpeeds.fromJson(r.toJson()).at(12000), 10);
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
