import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/convoy_event.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/data/models/waypoint.dart';
import 'package:convoy/services/invite/invite_links.dart';
import 'package:convoy/services/location/gps_service.dart';
import 'package:convoy/services/navigation/nav_handoff.dart';
import 'package:convoy/services/planning/trip_days.dart';
import 'package:convoy/services/safety/crash_detector.dart';
import 'package:convoy/services/tracking/convoy_events.dart';
import 'package:convoy/services/tracking/convoy_watch.dart';
import 'package:convoy/services/tracking/lead_vehicle.dart';
import 'package:convoy/services/tracking/safety_watch.dart';
import 'package:convoy/services/voice/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 11, 1, 9);
ConvoyEvent ev(String id, EventKind kind, String member, int minutes, {Map<String, dynamic> payload = const {}, GeoPoint? at}) =>
    ConvoyEvent(id: id, tripId: 't', memberId: member, kind: kind, createdAt: t0.add(Duration(minutes: minutes)), payload: payload, location: at);
VehiclePosition pos(String m, GeoPoint p, {double kmh = 0, DateTime? at, double heading = 90}) =>
    VehiclePosition(memberId: m, point: p, timestamp: at ?? t0, speedMps: kmh / 3.6, headingDeg: heading);

// A straight east-west road, ~1.09 km per 0.01° of longitude at 12.9° N.
const road = [GeoPoint(12.9, 77.5), GeoPoint(12.9, 77.9)];
GeoPoint onRoad(double km) => GeoPoint(12.9, 77.5 + km / 108.5);

void main() {
  group('convoy event state', () {
    test('SOS stays until cleared by its owner or resolved by reference', () {
      var s = ConvoyEventState.from([ev('1', EventKind.sos, 'bob', 0)], t0);
      expect(s.sos.keys, ['bob']);
      s = ConvoyEventState.from([ev('1', EventKind.sos, 'bob', 0), ev('2', EventKind.sosClear, 'bob', 2)], t0);
      expect(s.sos, isEmpty);
      s = ConvoyEventState.from([ev('1', EventKind.sos, 'bob', 0), ev('2', EventKind.sosClear, 'alice', 2, payload: {'ref': '1'})], t0);
      expect(s.sos, isEmpty);
    });

    test('hazards expire by type and can be cleared', () {
      final police = ev('p', EventKind.hazard, 'a', 0, payload: {'type': 'police'});
      final pothole = ev('h', EventKind.hazard, 'a', 0, payload: {'type': 'pothole'});
      expect(ConvoyEventState.from([police, pothole], t0.add(const Duration(hours: 2))).hazards.map((h) => h.id), ['h']);
      expect(ConvoyEventState.from([pothole, ev('c', EventKind.hazardClear, 'b', 5, payload: {'ref': 'h'})], t0).hazards, isEmpty);
    });

    test('headcount collects ready taps until go', () {
      final events = [ev('h', EventKind.headcount, 'lead', 0), ev('r1', EventKind.ready, 'bob', 1), ev('r2', EventKind.ready, 'cara', 2)];
      expect(ConvoyEventState.from(events, t0).headcount!.ready, {'lead', 'bob', 'cara'});
      expect(ConvoyEventState.from([...events, ev('g', EventKind.go, 'lead', 3)], t0).headcount, isNull);
      // A ready tap with no open headcount counts for nothing.
      expect(ConvoyEventState.from([ev('r', EventKind.ready, 'bob', 0)], t0).headcount, isNull);
    });

    test('a new regroup point replaces the old one', () {
      final s = ConvoyEventState.from([ev('a', EventKind.regroup, 'x', 0), ev('b', EventKind.regroup, 'y', 1)], t0);
      expect(s.regroup!.id, 'b');
    });
  });

  group('driver nudges', () {
    test('suggests a break after two hours of driving, and again 30 min later', () {
      final n = DriverNudges();
      List<ConvoyAlert> at(int min, double kmh) =>
          n.evaluate(now: t0.add(Duration(minutes: min)), me: pos('me', road.first, kmh: kmh, at: t0.add(Duration(minutes: min))));
      expect(at(0, 80), isEmpty);
      expect(at(119, 80), isEmpty);
      expect(at(120, 80).single.kind, AlertKind.fatigue);
      expect(at(130, 80), isEmpty);
      expect(at(150, 80).single.kind, AlertKind.fatigue);
    });

    test('a 10-minute stop resets driving time', () {
      final n = DriverNudges();
      n.evaluate(now: t0, me: pos('me', road.first, kmh: 80, at: t0));
      for (var m = 100; m <= 112; m++) {
        n.evaluate(now: t0.add(Duration(minutes: m)), me: pos('me', road.first, at: t0.add(Duration(minutes: m))));
      }
      expect(n.drivingFor(t0.add(const Duration(minutes: 112))), Duration.zero);
    });

    test('pace nudge only when well above the convoy for a minute', () {
      final n = DriverNudges();
      List<ConvoyAlert> at(int s, double kmh, double convoy) =>
          n.evaluate(now: t0.add(Duration(seconds: s)), me: pos('me', road.first, kmh: kmh, at: t0.add(Duration(seconds: s))), convoyKmh: convoy);
      expect(at(0, 110, 70), isEmpty);
      expect(at(61, 110, 70).single.kind, AlertKind.pace);
      expect(at(120, 110, 70), isEmpty); // cooldown
      expect(n.evaluate(now: t0, me: pos('x', road.first, kmh: 90, at: t0), convoyKmh: 80), isEmpty);
    });
  });

  test('sweep is told about a car behind it', () {
    final w = SweepWatch();
    List<ConvoyStanding> standings(double behindKm) => [
          const ConvoyStanding(memberId: 'sweep', alongMeters: 5000, gapToLeadMeters: 0, offRouteMeters: 0, stale: false),
          ConvoyStanding(memberId: 'thar', alongMeters: 5000 - behindKm * 1000, gapToLeadMeters: 0, offRouteMeters: 0, stale: false),
        ];
    expect(w.evaluate(now: t0, sweepId: 'sweep', standings: standings(1), labels: {'thar': 'Thar'}), isEmpty);
    final a = w.evaluate(now: t0.add(const Duration(seconds: 31)), sweepId: 'sweep', standings: standings(1), labels: {'thar': 'Thar'});
    expect(a.single.message, startsWith('Thar is behind you'));
    expect(w.evaluate(now: t0.add(const Duration(seconds: 40)), sweepId: 'sweep', standings: standings(0.1), labels: {}), isEmpty);
  });

  test('hazards are announced once, only when ahead on the route', () {
    final w = HazardAhead();
    final hazard = ev('h', EventKind.hazard, 'other', 0, payload: {'type': 'pothole'}, at: onRoad(10));
    expect(w.evaluate(now: t0, me: pos('me', onRoad(5)), hazards: [hazard], route: road), isEmpty); // 5 km away
    final a = w.evaluate(now: t0, me: pos('me', onRoad(8.5)), hazards: [hazard], route: road);
    expect(a.single.message, 'Pothole reported 1.5 km ahead.');
    expect(w.evaluate(now: t0, me: pos('me', onRoad(9)), hazards: [hazard], route: road), isEmpty);
    // Already past it.
    expect(HazardAhead().evaluate(now: t0, me: pos('me', onRoad(11)), hazards: [hazard], route: road), isEmpty);
  });

  test('regroup ETA uses road distance and marks arrivals', () {
    final etas = RegroupEta.compute(
      point: onRoad(10),
      positions: {'a': pos('a', onRoad(10.05)), 'b': pos('b', onRoad(4), kmh: 60)},
      route: road,
    );
    expect(etas.first.memberId, 'a');
    expect(etas.first.arrived, isTrue);
    expect(etas.last.distanceMeters, closeTo(6000, 100));
    expect(etas.last.eta!.inMinutes, closeTo(6, 1));
  });

  test('fuel warning when range will not reach the next fuel stop', () {
    final stops = [(name: 'HP Maddur', alongKm: 150.0)];
    final s = FuelStatus.evaluate(rangeKm: 90, myAlongKm: 10, fuelStops: stops, routeKm: 300);
    expect(s.nextFuelKm, 140);
    expect(s.warn, isTrue);
    expect(FuelStatus.evaluate(rangeKm: 400, myAlongKm: 10, fuelStops: stops, routeKm: 300).warn, isFalse);
    // No fuel stop planned: compare with the rest of the route.
    expect(FuelStatus.evaluate(rangeKm: 100, myAlongKm: 0, fuelStops: const [], routeKm: 238).warn, isTrue);
  });

  test('trip cost: fuel by economy and price, tolls by plaza', () {
    final c = TripCost.estimate(distanceKm: 240, kmpl: 12, fuelPrice: 105, plazas: 3, tollPerPlaza: 120);
    expect(c.fuelLitres, 20);
    expect(c.fuelCost, 2100);
    expect(c.tollCost, 360);
    expect(c.total, 2460);
    expect(TripCost.estimate(distanceKm: 240, plazas: 2).total, isNull);
  });

  group('crash detection', () {
    test('a hard impact while driving followed by a stop is a crash', () {
      final d = CrashDetector();
      d.onSpeed(t0, 70 / 3.6);
      expect(d.onImpact(t0.add(const Duration(seconds: 1)), 60), isTrue);
      d.onSpeed(t0.add(const Duration(seconds: 4)), 0);
      expect(d.check(t0.add(const Duration(seconds: 5))), isTrue);
      expect(d.check(t0.add(const Duration(seconds: 6))), isFalse);
    });

    test('no GPS fixes after the impact means the car stopped', () {
      final d = CrashDetector()..onSpeed(t0, 80 / 3.6);
      d.onImpact(t0.add(const Duration(seconds: 1)), 70);
      expect(d.check(t0.add(const Duration(seconds: 3))), isFalse);
      expect(d.check(t0.add(const Duration(seconds: 7))), isTrue);
    });

    test('a dropped phone at a standstill or an impact without stopping is not', () {
      final parked = CrashDetector()..onSpeed(t0, 0);
      expect(parked.onImpact(t0.add(const Duration(seconds: 1)), 80), isFalse);
      final bump = CrashDetector()..onSpeed(t0, 70 / 3.6);
      bump.onImpact(t0.add(const Duration(seconds: 1)), 50);
      bump.onSpeed(t0.add(const Duration(seconds: 4)), 65 / 3.6);
      expect(bump.check(t0.add(const Duration(seconds: 5))), isFalse);
      expect(bump.check(t0.add(const Duration(seconds: 20))), isFalse);
    });
  });

  group('voice commands', () {
    test('broadcasts keep the driver\'s words', () {
      final c = VoiceCommands.parse('Hey DriveSync, tell everyone fuel stop in 10 minutes.');
      expect((c as Broadcast).text, 'Fuel stop in 10 minutes');
      expect((VoiceCommands.parse('let everyone know we are stopping for chai') as Broadcast).text, 'We are stopping for chai');
    });

    test('recognises the fixed phrasings', () {
      expect(VoiceCommands.parse('where is the lead car'), isA<WhereIsLead>());
      expect(VoiceCommands.parse('how far to the next stop'), isA<NextStop>());
      expect(VoiceCommands.parse('SOS'), isA<RaiseSos>());
      expect((VoiceCommands.parse('report a pothole') as ReportHazard).type, HazardType.pothole);
      expect((VoiceCommands.parse("there's police ahead") as ReportHazard).type, HazardType.police);
      expect(VoiceCommands.parse("I'm ready"), isA<ReadyToGo>());
      expect(VoiceCommands.parse('regroup here'), isA<RegroupHere>());
      expect((VoiceCommands.parse('running fifteen minutes late') as RunningLate).minutes, 15);
      expect((VoiceCommands.parse('where is Priya') as WhereIs).name, 'priya');
      expect(VoiceCommands.parse('play some music'), isA<Unknown>());
    });

    test('detects the wake phrase', () {
      expect(VoiceCommands.hasWakeWord('Hey Drive Sync where is the lead'), isTrue);
      expect(VoiceCommands.hasWakeWord('where is the lead'), isFalse);
    });
  });

  test('invite codes come from links, the app scheme or plain text', () {
    expect(InviteLinks.codeFrom('https://edge.example/j/k7q2m9xp'), 'K7Q2M9XP');
    expect(InviteLinks.codeFrom('drivesync://join/K7Q2M9XP'), 'K7Q2M9XP');
    expect(InviteLinks.codeFrom(' k7q2-m9xp '), 'K7Q2M9XP');
    expect(InviteLinks.codeFrom('https://evil.example/login'), isNull);
    expect(InviteLinks.codeFrom('hello'), isNull);
  });

  test('navigation links start driving directions', () {
    const to = GeoPoint(12.3052, 76.6552);
    expect(NavHandoff.uri(NavApp.googleMaps, to).toString(), 'google.navigation:q=12.305200,76.655200&mode=d');
    final osmand = NavHandoff.uri(NavApp.osmAnd, to, name: 'Mysuru');
    expect(osmand.queryParameters['dest_name'], 'Mysuru');
    expect(osmand.queryParameters['profile'], 'car');
    expect(NavHandoff.uri(NavApp.waze, to).toString(), contains('navigate=yes'));
  });

  group('multi-day trips', () {
    Waypoint wp(String id, double km, {int? day, DateTime? arrive, WaypointKind kind = WaypointKind.waypoint}) => Waypoint(
        id: id, tripId: 't', name: id, location: onRoad(km), kind: kind, sortKey: km, hlc: '0', day: day, plannedArrival: arrive);

    test('days come from the stop, its arrival date, or the stop before', () {
      final days = TripDays.assign([
        wp('a', 0),
        wp('b', 50),
        wp('c', 100, arrive: DateTime(2026, 11, 2, 9)),
        wp('d', 150),
        wp('e', 200, day: 3),
      ], tripStart: DateTime(2026, 11, 1, 6));
      expect(days, {'a': 1, 'b': 1, 'c': 2, 'd': 2, 'e': 3});
    });

    test('each day measures from where the night was spent', () {
      final split = TripDays.split([
        wp('start', 0, day: 1),
        wp('camp', 120, day: 1, kind: WaypointKind.campsite),
        wp('lunch', 180, day: 2),
        wp('end', 250, day: 2, kind: WaypointKind.destination),
      ], [onRoad(0), onRoad(300)]);
      expect(split.length, 2);
      expect(split[0].distanceMeters / 1000, closeTo(120, 1));
      expect(split[0].overnight!.id, 'camp');
      expect(split[1].distanceMeters / 1000, closeTo(130, 1));
      expect(split[1].overnight, isNull);
    });
  });

  test('GPS drops to the parked rate after three still minutes and wakes on movement', () {
    final g = GpsService(memberId: 'me');
    expect(g.shouldPark(pos('me', onRoad(1)), t0), isFalse);
    expect(g.shouldPark(pos('me', onRoad(1.01)), t0.add(const Duration(minutes: 2))), isFalse);
    expect(g.shouldPark(pos('me', onRoad(1.01)), t0.add(const Duration(minutes: 3))), isTrue);
    expect(g.shouldPark(pos('me', onRoad(1.01), kmh: 20), t0.add(const Duration(minutes: 4))), isFalse);
  });
}
