import 'dart:math' as math;

/// A WGS84 coordinate. Kept independent of any map SDK so the sync, tracking
/// and mesh layers stay pure Dart and unit-testable.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  factory GeoBounds.around(Iterable<GeoPoint> points, {double padMeters = 0}) {
    final list = points.toList();
    if (list.isEmpty) {
      throw ArgumentError('GeoBounds.around needs at least one point');
    }
    var s = list.first.lat, n = s, w = list.first.lng, e = w;
    for (final p in list.skip(1)) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lng);
      e = math.max(e, p.lng);
    }
    final b = GeoBounds(south: s, west: w, north: n, east: e);
    return padMeters > 0 ? b.pad(padMeters) : b;
  }

  /// Grows the box by [meters] on every side.
  GeoBounds pad(double meters) {
    final dLat = meters / Geo.metersPerDegreeLat;
    final midLat = (south + north) / 2;
    final dLng = meters / (Geo.metersPerDegreeLat * math.cos(Geo.rad(midLat)).abs().clamp(0.01, 1.0));
    return GeoBounds(
      south: (south - dLat).clamp(-85.0511, 85.0511),
      north: (north + dLat).clamp(-85.0511, 85.0511),
      west: (west - dLng).clamp(-180.0, 180.0),
      east: (east + dLng).clamp(-180.0, 180.0),
    );
  }

  bool contains(GeoPoint p) =>
      p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  /// Approximate area in km², used to price offline downloads against the
  /// subscription tier.
  double get areaKm2 {
    final h = Geo.distanceMeters(GeoPoint(south, west), GeoPoint(north, west));
    final midLat = (south + north) / 2;
    final w = Geo.distanceMeters(GeoPoint(midLat, west), GeoPoint(midLat, east));
    return h * w / 1e6;
  }

  Map<String, dynamic> toJson() =>
      {'south': south, 'west': west, 'north': north, 'east': east};

  factory GeoBounds.fromJson(Map<String, dynamic> j) => GeoBounds(
        south: (j['south'] as num).toDouble(),
        west: (j['west'] as num).toDouble(),
        north: (j['north'] as num).toDouble(),
        east: (j['east'] as num).toDouble(),
      );
}

abstract final class Geo {
  static const double earthRadiusM = 6371008.8;
  static const double metersPerDegreeLat = 111320.0;

  static double rad(double deg) => deg * math.pi / 180.0;
  static double deg(double rad) => rad * 180.0 / math.pi;

  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// Initial bearing from [a] to [b], degrees clockwise from north, 0..360.
  static double bearingDeg(GeoPoint a, GeoPoint b) {
    final phi1 = rad(a.lat), phi2 = rad(b.lat);
    final dLng = rad(b.lng - a.lng);
    final y = math.sin(dLng) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
    return (deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Point reached travelling [distanceM] from [start] on [bearing] degrees.
  static GeoPoint destination(GeoPoint start, double bearing, double distanceM) {
    final delta = distanceM / earthRadiusM;
    final theta = rad(bearing);
    final phi1 = rad(start.lat), lambda1 = rad(start.lng);
    final phi2 = math.asin(math.sin(phi1) * math.cos(delta) +
        math.cos(phi1) * math.sin(delta) * math.cos(theta));
    final lambda2 = lambda1 +
        math.atan2(math.sin(theta) * math.sin(delta) * math.cos(phi1),
            math.cos(delta) - math.sin(phi1) * math.sin(phi2));
    return GeoPoint(deg(phi2), ((deg(lambda2) + 540) % 360) - 180);
  }

  /// Distance travelled along [route] to the point on it closest to [p].
  /// Used to rank vehicles by progress (lead detection, "who is behind").
  static RouteProjection projectOntoRoute(List<GeoPoint> route, GeoPoint p) {
    if (route.isEmpty) return const RouteProjection(0, double.infinity, 0);
    if (route.length == 1) {
      return RouteProjection(0, distanceMeters(route.first, p), 0);
    }
    var best = const RouteProjection(0, double.infinity, 0);
    var walked = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i], b = route[i + 1];
      final segLen = distanceMeters(a, b);
      // Local equirectangular projection is accurate enough per segment.
      final cosLat = math.cos(rad((a.lat + b.lat) / 2));
      final ax = a.lng * cosLat, ay = a.lat;
      final bx = b.lng * cosLat, by = b.lat;
      final px = p.lng * cosLat, py = p.lat;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
      final proj = GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
      final off = distanceMeters(proj, p);
      if (off < best.offRouteMeters) {
        best = RouteProjection(walked + segLen * t, off, i);
      }
      walked += segLen;
    }
    return best;
  }

  static double routeLength(List<GeoPoint> route) {
    var total = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      total += distanceMeters(route[i], route[i + 1]);
    }
    return total;
  }

  /// Splits a route into overlapping boxes no larger than [maxSpanM] so the
  /// offline downloader caches a corridor rather than one huge rectangle.
  static List<GeoBounds> corridorBoxes(List<GeoPoint> route,
      {double maxSpanM = 60000, double padM = 8000}) {
    if (route.isEmpty) return const [];
    final boxes = <GeoBounds>[];
    var chunk = <GeoPoint>[route.first];
    for (final p in route.skip(1)) {
      chunk.add(p);
      final b = GeoBounds.around(chunk);
      final span = distanceMeters(GeoPoint(b.south, b.west), GeoPoint(b.north, b.east));
      if (span >= maxSpanM) {
        boxes.add(GeoBounds.around(chunk, padMeters: padM));
        chunk = <GeoPoint>[p];
      }
    }
    if (chunk.length > 1 || boxes.isEmpty) {
      boxes.add(GeoBounds.around(chunk, padMeters: padM));
    }
    return boxes;
  }

  static String compass(double bearing) {
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return names[((bearing % 360) / 45).round() % 8];
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
  }
}

class RouteProjection {
  const RouteProjection(this.alongMeters, this.offRouteMeters, this.segmentIndex);

  final double alongMeters;
  final double offRouteMeters;
  final int segmentIndex;
}
