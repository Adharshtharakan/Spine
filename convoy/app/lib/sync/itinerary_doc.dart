import '../core/geo/geo.dart';
import '../data/models/waypoint.dart';
import 'hlc.dart';

/// The replicated itinerary for one trip.
///
/// A state-based CRDT: a map of waypoint id → latest row, where "latest" is
/// decided by HLC. Deletes are tombstones so a stale offline edit cannot
/// resurrect a removed stop. Merging is commutative, associative and
/// idempotent, so it does not matter whether a change arrives through
/// Supabase Realtime, the offline outbox replay, or the mesh.
class ItineraryDoc {
  ItineraryDoc(this.tripId, {required this.nodeId, Map<String, Waypoint>? rows})
      : _rows = rows ?? {},
        _clock = Hlc.zero(nodeId);

  final String tripId;
  final String nodeId;
  final Map<String, Waypoint> _rows;
  Hlc _clock;

  Hlc get clock => _clock;

  /// Visible stops in route order.
  List<Waypoint> get waypoints {
    final list = _rows.values.where((w) => !w.deleted).toList()
      ..sort((a, b) {
        final c = a.sortKey.compareTo(b.sortKey);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  List<GeoPoint> get route => waypoints.map((w) => w.location).toList();

  Waypoint? operator [](String id) => _rows[id];

  Iterable<Waypoint> get allRows => _rows.values;

  /// Merges a row from any source. Returns true if visible state changed.
  bool merge(Waypoint incoming, {int? nowMs}) {
    _clock = _clock.receive(Hlc.parse(incoming.hlc),
        nowMs ?? DateTime.now().millisecondsSinceEpoch);
    final current = _rows[incoming.id];
    if (current != null && current.hlc.compareTo(incoming.hlc) >= 0) {
      return false;
    }
    _rows[incoming.id] = incoming;
    return true;
  }

  bool mergeAll(Iterable<Waypoint> rows, {int? nowMs}) {
    var changed = false;
    for (final r in rows) {
      changed = merge(r, nowMs: nowMs) || changed;
    }
    return changed;
  }

  String _tick(int? nowMs) {
    _clock = _clock.send(nowMs ?? DateTime.now().millisecondsSinceEpoch);
    return _clock.toString();
  }

  /// Local edit helpers. Each returns the row to persist / broadcast.
  Waypoint insert({
    required String id,
    required String name,
    required GeoPoint location,
    WaypointKind kind = WaypointKind.waypoint,
    String? afterId,
    DateTime? plannedArrival,
    DateTime? plannedDeparture,
    String notes = '',
    String? userId,
    int? nowMs,
  }) {
    final row = Waypoint(
      id: id,
      tripId: tripId,
      name: name,
      location: location,
      kind: kind,
      sortKey: _sortKeyAfter(afterId),
      hlc: _tick(nowMs),
      plannedArrival: plannedArrival,
      plannedDeparture: plannedDeparture,
      notes: notes,
      updatedBy: userId,
    );
    _rows[id] = row;
    return row;
  }

  Waypoint update(String id, Waypoint Function(Waypoint) edit,
      {String? userId, int? nowMs}) {
    final current = _rows[id];
    if (current == null) throw StateError('Unknown waypoint $id');
    final row = edit(current).copyWith(hlc: _tick(nowMs), updatedBy: userId);
    _rows[id] = row;
    return row;
  }

  Waypoint remove(String id, {String? userId, int? nowMs}) =>
      update(id, (w) => w.copyWith(deleted: true), userId: userId, nowMs: nowMs);

  /// Moves [id] to sit directly after [afterId] (or first when null).
  Waypoint move(String id, String? afterId, {String? userId, int? nowMs}) {
    final key = _sortKeyAfter(afterId, excluding: id);
    return update(id, (w) => w.copyWith(sortKey: key), userId: userId, nowMs: nowMs);
  }

  /// Shifts the schedule of [fromId] and every later stop by [delta] — the
  /// "we're running 40 minutes late" operation.
  List<Waypoint> shiftSchedule(String fromId, Duration delta,
      {String? userId, int? nowMs}) {
    final list = waypoints;
    final start = list.indexWhere((w) => w.id == fromId);
    if (start < 0) return const [];
    final changed = <Waypoint>[];
    for (final w in list.sublist(start)) {
      if (w.plannedArrival == null && w.plannedDeparture == null) continue;
      changed.add(update(
        w.id,
        (x) => x.copyWith(
          plannedArrival: x.plannedArrival?.add(delta),
          plannedDeparture: x.plannedDeparture?.add(delta),
        ),
        userId: userId,
        nowMs: nowMs,
      ));
    }
    return changed;
  }

  double _sortKeyAfter(String? afterId, {String? excluding}) {
    final list = waypoints.where((w) => w.id != excluding).toList();
    if (list.isEmpty) return 1024;
    if (afterId == null) return list.first.sortKey / 2;
    final i = list.indexWhere((w) => w.id == afterId);
    if (i < 0 || i == list.length - 1) return list.last.sortKey + 1024;
    return (list[i].sortKey + list[i + 1].sortKey) / 2;
  }

  /// The next stop the convoy has not yet reached, given the lead vehicle's
  /// distance along the route.
  Waypoint? nextStop(double leadAlongMeters) {
    final r = route;
    if (r.isEmpty) return null;
    for (final w in waypoints) {
      final along = Geo.projectOntoRoute(r, w.location).alongMeters;
      if (along > leadAlongMeters + 150) return w;
    }
    return null;
  }
}
