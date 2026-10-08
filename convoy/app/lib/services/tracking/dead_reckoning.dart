import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';

/// Keeps a silent vehicle on the map when neither the cloud nor the mesh can
/// reach it: its last fix is projected forward, preferring to follow the
/// shared route (convoys rarely leave it) and falling back to straight-line
/// heading. The uncertainty radius grows with time so drivers can see how
/// much to trust it.
class DeadReckoning {
  const DeadReckoning({
    this.maxProjection = const Duration(minutes: 20),
    this.uncertaintyGrowthMps = 6,
  });

  final Duration maxProjection;
  final double uncertaintyGrowthMps;

  VehiclePosition estimate(VehiclePosition last, List<GeoPoint> route, DateTime now) {
    final elapsed = now.difference(last.timestamp);
    if (elapsed <= Duration.zero || last.speedMps < 0.5) return last;
    final secs = math.min(elapsed.inMilliseconds, maxProjection.inMilliseconds) / 1000.0;
    final travel = last.speedMps * secs;
    final radius = last.accuracyM + uncertaintyGrowthMps * secs;

    GeoPoint projected;
    if (route.length >= 2) {
      final proj = Geo.projectOntoRoute(route, last.point);
      projected = proj.offRouteMeters < 300
          ? pointAlong(route, proj.alongMeters + travel)
          : Geo.destination(last.point, last.headingDeg, travel);
    } else {
      projected = Geo.destination(last.point, last.headingDeg, travel);
    }
    return last.copyWith(
      point: projected,
      source: PositionSource.estimated,
      accuracyM: radius,
    );
  }

  static GeoPoint pointAlong(List<GeoPoint> route, double meters) {
    if (meters <= 0) return route.first;
    var walked = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final seg = Geo.distanceMeters(route[i], route[i + 1]);
      if (walked + seg >= meters) {
        final t = seg == 0 ? 0.0 : (meters - walked) / seg;
        return GeoPoint(
          route[i].lat + (route[i + 1].lat - route[i].lat) * t,
          route[i].lng + (route[i + 1].lng - route[i].lng) * t,
        );
      }
      walked += seg;
    }
    return route.last;
  }
}
