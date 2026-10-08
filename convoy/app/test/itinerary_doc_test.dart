import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/data/models/waypoint.dart';
import 'package:convoy/sync/hlc.dart';
import 'package:convoy/sync/itinerary_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  group('Hlc', () {
    test('string order equals clock order', () {
      final c1 = const Hlc(1000, 0, 'n1');
      final c2 = c1.send(1000);
      final c3 = c2.send(2000);
      expect(c2 > c1, isTrue);
      expect(c3 > c2, isTrue);
      expect(Hlc.parse(c3.toString()), c3);
    });

    test('receive moves past a remote clock ahead of local wall time', () {
      const local = Hlc(1000, 0, 'n1');
      const remote = Hlc(5000, 3, 'n2');
      final merged = local.receive(remote, 2000);
      expect(merged.millis, 5000);
      expect(merged.counter, 4);
    });

    test('ignores remote clocks too far in the future', () {
      const local = Hlc(1000, 0, 'n1');
      final remote = Hlc(1000 + Hlc.maxDriftMs * 10, 0, 'n2');
      expect(local.receive(remote, 1000).millis, 1000);
    });
  });

  group('ItineraryDoc', () {
    test('inserts keep requested order', () {
      final doc = ItineraryDoc('t', nodeId: 'n1');
      doc.insert(id: 'w1', name: 'Start', location: const GeoPoint(0, 0), nowMs: 1);
      doc.insert(id: 'w3', name: 'End', location: const GeoPoint(0, 2), afterId: 'w1', nowMs: 2);
      doc.insert(id: 'w2', name: 'Mid', location: const GeoPoint(0, 1), afterId: 'w1', nowMs: 3);
      expect(doc.waypoints.map((w) => w.id), ['w1', 'w2', 'w3']);
      doc.move('w3', null, nowMs: 4);
      expect(doc.waypoints.map((w) => w.id), ['w3', 'w1', 'w2']);
    });

    test('concurrent edits converge regardless of arrival order', () {
      final base = ItineraryDoc('t', nodeId: 'n0');
      final seed = base.insert(id: 'w1', name: 'Diner', location: const GeoPoint(1, 1), nowMs: 10);

      final phoneA = ItineraryDoc('t', nodeId: 'a')..merge(seed, nowMs: 10);
      final phoneB = ItineraryDoc('t', nodeId: 'b')..merge(seed, nowMs: 10);

      final editA = phoneA.update('w1', (w) => w.copyWith(name: 'Diner (closed)'), nowMs: 20);
      final editB = phoneB.update('w1', (w) => w.copyWith(notes: 'meet here'), nowMs: 30);

      phoneA.merge(editB, nowMs: 31);
      phoneB.merge(editA, nowMs: 31);
      expect(phoneA['w1']!.hlc, phoneB['w1']!.hlc);
      expect(phoneA['w1']!.notes, 'meet here');
      expect(phoneB['w1']!.notes, 'meet here');
    });

    test('a stale offline edit cannot resurrect a deleted stop', () {
      final a = ItineraryDoc('t', nodeId: 'a');
      final seed = a.insert(id: 'w1', name: 'Camp', location: const GeoPoint(1, 1), nowMs: 10);
      final b = ItineraryDoc('t', nodeId: 'b')..merge(seed, nowMs: 10);

      final staleEdit = b.update('w1', (w) => w.copyWith(name: 'Camp 2'), nowMs: 11);
      final delete = a.remove('w1', nowMs: 50);

      a.merge(staleEdit, nowMs: 60);
      b.merge(delete, nowMs: 60);
      expect(a.waypoints, isEmpty);
      expect(b.waypoints, isEmpty);
    });

    test('merge is idempotent', () {
      final a = ItineraryDoc('t', nodeId: 'a');
      final row = a.insert(id: 'w1', name: 'x', location: const GeoPoint(0, 0), nowMs: 1);
      final b = ItineraryDoc('t', nodeId: 'b');
      expect(b.merge(row, nowMs: 2), isTrue);
      expect(b.merge(row, nowMs: 3), isFalse);
    });

    test('shiftSchedule moves this and every later timed stop', () {
      final doc = ItineraryDoc('t', nodeId: 'n');
      final t0 = DateTime.utc(2026, 10, 1, 8);
      doc.insert(id: 'w1', name: 'a', location: const GeoPoint(0, 0), plannedDeparture: t0, nowMs: 1);
      doc.insert(id: 'w2', name: 'b', location: const GeoPoint(0, 1), afterId: 'w1',
          plannedArrival: t0.add(const Duration(hours: 1)), nowMs: 2);
      doc.insert(id: 'w3', name: 'c', location: const GeoPoint(0, 2), afterId: 'w2',
          plannedArrival: t0.add(const Duration(hours: 2)), nowMs: 3);

      final changed = doc.shiftSchedule('w2', const Duration(minutes: 40), nowMs: 4);
      expect(changed.map((w) => w.id), ['w2', 'w3']);
      expect(doc['w1']!.plannedDeparture, t0);
      expect(doc['w2']!.plannedArrival, t0.add(const Duration(hours: 1, minutes: 40)));
    });

    test('rows round-trip through the database shape', () {
      final doc = ItineraryDoc(_a, nodeId: 'n');
      final row = doc.insert(
          id: _b, name: 'Fuel', location: const GeoPoint(12.5, 77.6), kind: WaypointKind.fuel, nowMs: 1);
      final back = Waypoint.fromRow(row.toRow());
      expect(back.kind, WaypointKind.fuel);
      expect(back.location, row.location);
      expect(back.hlc, row.hlc);
    });
  });
}
