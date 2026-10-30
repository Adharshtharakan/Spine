import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/data/models/waypoint.dart';
import 'package:convoy/services/tracking/convoy_watch.dart';
import 'package:convoy/services/tracking/lead_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _me = 'cccccccc-0000-4000-8000-000000000003';
const _route = [GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(0, 2)];
const _labels = {_a: 'Innova', _b: 'Thar', _me: 'Swift'};
const _m = 111195.0; // metres per degree at the equator

VehiclePosition _at(String id, double meters, DateTime t, {double speed = 25, double lat = 0}) =>
    VehiclePosition(memberId: id, point: GeoPoint(lat, meters / _m), timestamp: t, speedMps: speed, headingDeg: 90);

List<ConvoyAlert> _eval(ConvoyWatch w, Map<String, VehiclePosition> pos, DateTime now,
    {List<Waypoint> stops = const [], bool selfOnline = true}) {
  const resolver = LeadVehicleResolver();
  final lead = resolver.resolve(designatedMemberId: _a, positions: pos, route: _route, now: now);
  return w.evaluate(
    now: now,
    reported: pos,
    standings: resolver.standings(lead: lead, positions: pos, route: _route, now: now),
    route: _route,
    stops: stops,
    labels: _labels,
    selfId: _me,
    selfOnline: selfOnline,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 10, 23, 10);

  test('falling behind fires once the gap persists, once, then re-arms after clearing', () {
    final w = ConvoyWatch();
    Map<String, VehiclePosition> spread(DateTime t, double gap) =>
        {_a: _at(_a, 50000, t), _b: _at(_b, 50000 - gap, t), _me: _at(_me, 50000 - gap - 200, t)};

    // 25 m/s → threshold max(1500, 90 × 25) = 2250 m. A 3 km gap:
    expect(_eval(w, spread(t0, 3000), t0), isEmpty, reason: 'not yet held for 30 s');
    final fired = _eval(w, spread(t0.add(const Duration(seconds: 31)), 3000), t0.add(const Duration(seconds: 31)));
    expect(fired.single.kind, AlertKind.fallingBehind);
    expect(fired.single.memberId, _b);
    expect(fired.single.message, 'Thar is 3.0 km behind Innova');
    expect(_eval(w, spread(t0.add(const Duration(seconds: 60)), 3000), t0.add(const Duration(seconds: 60))), isEmpty,
        reason: 'no repeats while still behind');

    // Caught up, then fell behind again after the cooldown.
    _eval(w, spread(t0.add(const Duration(minutes: 2)), 500), t0.add(const Duration(minutes: 2)));
    final later = t0.add(const Duration(minutes: 13));
    _eval(w, spread(later, 3000), later);
    expect(_eval(w, spread(later.add(const Duration(seconds: 31)), 3000), later.add(const Duration(seconds: 31))), hasLength(1));
  });

  test('normal highway spacing does not alert', () {
    final w = ConvoyWatch();
    final pos = {_a: _at(_a, 50000, t0), _b: _at(_b, 48200, t0), _me: _at(_me, 46500, t0)};
    _eval(w, pos, t0);
    expect(_eval(w, pos, t0.add(const Duration(minutes: 2))), isEmpty);
  });

  test('tells you when it is you who is falling behind', () {
    final w = ConvoyWatch();
    Map<String, VehiclePosition> pos(DateTime t) => {_a: _at(_a, 50000, t), _me: _at(_me, 46000, t)};
    _eval(w, pos(t0), t0);
    final a = _eval(w, pos(t0.add(const Duration(seconds: 31))), t0.add(const Duration(seconds: 31))).single;
    expect(a.message, startsWith('You are 4.0 km behind'));
    expect(a.spoken, contains('You are falling behind'));
  });

  test('off route after 45 s while moving', () {
    final w = ConvoyWatch();
    Map<String, VehiclePosition> pos(DateTime t) => {_a: _at(_a, 50000, t), _b: _at(_b, 49000, t, lat: 0.009)}; // ~1 km off
    _eval(w, pos(t0), t0);
    expect(_eval(w, pos(t0.add(const Duration(seconds: 30))), t0.add(const Duration(seconds: 30))), isEmpty);
    final a = _eval(w, pos(t0.add(const Duration(seconds: 46))), t0.add(const Duration(seconds: 46)));
    expect(a.map((x) => x.kind), contains(AlertKind.offRoute));
  });

  test('unplanned stop, but not at a planned stop', () {
    Waypoint stop(double m) => Waypoint(
        id: 's', tripId: 't', name: 'Dhaba', location: GeoPoint(0, m / _m), kind: WaypointKind.restStop, sortKey: 1, hlc: 'x');

    for (final (stops, expectAlert) in [(<Waypoint>[], true), ([stop(30100)], false)]) {
      final w = ConvoyWatch();
      _eval(w, {_a: _at(_a, 30000, t0)}, t0, stops: stops); // moving
      final t = t0.add(const Duration(minutes: 4));
      final out = _eval(w, {_a: _at(_a, 30000, t, speed: 0)}, t, stops: stops);
      expect(out.any((x) => x.kind == AlertKind.unplannedStop), expectAlert);
    }
  });

  test('lost contact only for cars live this session, and not while we are offline', () {
    final w = ConvoyWatch();
    final live = {_a: _at(_a, 30000, t0), _b: _at(_b, 29000, t0)};
    _eval(w, live, t0);
    final t = t0.add(const Duration(minutes: 6));
    expect(_eval(w, live, t, selfOnline: false).where((x) => x.kind == AlertKind.lostContact), isEmpty);
    final lost = _eval(w, live, t).where((x) => x.kind == AlertKind.lostContact).toList();
    expect(lost.map((x) => x.memberId), containsAll([_a, _b]));

    // A trip opened days later with old last-known positions: silence.
    final fresh = ConvoyWatch();
    expect(_eval(fresh, live, t0.add(const Duration(days: 3))), isEmpty);
  });

  test('plan changes are described for drivers', () {
    final before = Waypoint(
        id: 'w', tripId: 't', name: 'Lunch: Mysuru', location: const GeoPoint(12.3, 76.6), kind: WaypointKind.restStop,
        sortKey: 1, hlc: 'a', plannedArrival: DateTime(2026, 10, 23, 11, 30));
    final later = before.copyWith(plannedArrival: DateTime(2026, 10, 23, 12, 10), hlc: 'b');
    expect(ConvoyWatch.describePlanChange(before, later, by: 'Ravi', now: t0)!.message,
        'Plan updated. Ravi: Lunch: Mysuru now at 12:10');
    expect(ConvoyWatch.describePlanChange(null, before, by: null, now: t0)!.message, 'Plan updated. New stop Lunch: Mysuru at 11:30');
    expect(ConvoyWatch.describePlanChange(before, before.copyWith(deleted: true, hlc: 'c'), by: 'Priya', now: t0)!.message,
        'Plan updated. Priya: Lunch: Mysuru removed from the plan');
    expect(ConvoyWatch.describePlanChange(before, before.copyWith(notes: 'veg thali', hlc: 'd'), by: 'Ravi', now: t0), isNull,
        reason: 'notes are not worth interrupting a driver for');
  });
}
