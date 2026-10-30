import '../../core/geo/geo.dart';
import '../../data/models/waypoint.dart';

/// One day of a multi-day trip: its stops in order, the route length driven
/// that day, and where the night is spent.
class TripDay {
  const TripDay({required this.day, required this.stops, required this.distanceMeters, this.overnight});

  final int day;
  final List<Waypoint> stops;
  final double distanceMeters;

  /// The last stop of the day when it is lodging or a campsite.
  final Waypoint? overnight;
}

abstract final class TripDays {
  /// The day a stop belongs to: set explicitly; else from its planned
  /// arrival relative to the trip's start date; else the previous stop's day.
  static Map<String, int> assign(List<Waypoint> stops, {DateTime? tripStart}) {
    final out = <String, int>{};
    var current = 1;
    for (final w in stops) {
      int? d = w.day;
      if (d == null && tripStart != null && w.plannedArrival != null) {
        final start = DateTime(tripStart.year, tripStart.month, tripStart.day);
        final at = DateTime(w.plannedArrival!.year, w.plannedArrival!.month, w.plannedArrival!.day);
        final n = at.difference(start).inDays + 1;
        if (n >= 1 && n <= 60) d = n;
      }
      current = d ?? current;
      out[w.id] = current;
    }
    return out;
  }

  /// Groups [stops] by day. Each day's distance runs from the previous day's
  /// last stop (where you woke up) to the day's last stop, along [route].
  static List<TripDay> split(List<Waypoint> stops, List<GeoPoint> route, {DateTime? tripStart}) {
    final days = assign(stops, tripStart: tripStart);
    final byDay = <int, List<Waypoint>>{};
    for (final w in stops) {
      byDay.putIfAbsent(days[w.id]!, () => []).add(w);
    }
    final keys = byDay.keys.toList()..sort();
    final out = <TripDay>[];
    Waypoint? wokeAt;
    for (final k in keys) {
      final list = byDay[k]!;
      final from = wokeAt ?? list.first;
      final to = list.last;
      double dist;
      if (route.length >= 2) {
        dist = (Geo.projectOntoRoute(route, to.location).alongMeters - Geo.projectOntoRoute(route, from.location).alongMeters).abs();
      } else {
        dist = 0;
        var prev = from.location;
        for (final w in list) {
          dist += Geo.distanceMeters(prev, w.location);
          prev = w.location;
        }
      }
      final last = list.last;
      out.add(TripDay(
        day: k,
        stops: list,
        distanceMeters: dist,
        overnight: last.kind == WaypointKind.lodging || last.kind == WaypointKind.campsite ? last : null,
      ));
      wokeAt = last;
    }
    return out;
  }
}
