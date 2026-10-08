import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';

/// Last-resort estimate of where another car is when nothing reaches us
/// from it — computed entirely on this phone, with no data exchanged
/// during the outage.
///
/// Inputs are only what the phone already had: the car's last reported
/// location (GPS, or a coarser network/cell-tower fix — its accuracy radius
/// is carried forward), its average speed, the cached road route and the
/// trip plan. It combines:
///
/// 1. **Convoy-mates.** Cars travelling together move together. If another
///    car that is still reporting was close behind or ahead when this one
///    went quiet, keep the same gap to it. This is usually the best signal
///    and survives stops, traffic and slow climbs that a speed model misses.
/// 2. **Road geometry and speed.** Advance along the cached road route (not
///    straight lines between stops). Speed, in order of preference: the
///    car's smoothed recent speed; its average moving speed over the trip
///    (persisted, so it survives an app restart offline); the road's
///    expected speed from the cached route. Never faster than 125 % of what
///    the road allows.
/// 3. **The plan.** If the car reaches a planned stop whose departure time
///    has not come yet, hold it there until then.
/// 4. **Heading.** Off the route, extrapolate along the last heading, but
///    only for a few minutes.
///
/// The uncertainty radius grows with time, more slowly when a convoy-mate
/// anchors the estimate, so drivers can see how far to trust it. It is an
/// estimate, never presented as tracking.
class ConvoyPredictor {
  const ConvoyPredictor({
    this.maxProjection = const Duration(minutes: 30),
    this.maxOffRouteProjection = const Duration(minutes: 5),
    this.buddyMaxGapM = 3000,
    this.freshFor = const Duration(seconds: 60),
  });

  final Duration maxProjection;
  final Duration maxOffRouteProjection;
  final double buddyMaxGapM;
  final Duration freshFor;

  /// [history] holds recent fixes per member (oldest first), [labels] gives
  /// readable names for the explanation.
  VehiclePosition predict({
    required VehiclePosition last,
    required List<GeoPoint> route,
    required Map<String, List<VehiclePosition>> history,
    required Map<String, VehiclePosition> latest,
    required List<Waypoint> stops,
    required DateTime now,
    Map<String, String> labels = const {},
    double? averageSpeed,
    double? Function(double alongMeters)? roadSpeedAt,
  }) {
    final elapsed = now.difference(last.timestamp);
    if (elapsed <= Duration.zero) return last;
    final secs = math.min(elapsed.inMilliseconds, maxProjection.inMilliseconds) / 1000.0;

    final onRoute = route.length >= 2 ? Geo.projectOntoRoute(route, last.point) : null;
    final usable = onRoute != null && onRoute.offRouteMeters < 300;
    final routeLen = usable ? Geo.routeLength(route) : 0.0;

    // 1. Convoy-mate anchor.
    if (usable) {
      final buddy = _buddy(last, route, history, latest, now, onRoute.alongMeters);
      if (buddy != null) {
        final along = (buddy.buddyAlongNow + buddy.gapAtLast).clamp(onRoute.alongMeters, routeLen);
        return last.copyWith(
          point: pointAlong(route, along),
          source: PositionSource.estimated,
          speedMps: buddy.buddySpeed,
          headingDeg: _headingAt(route, along, last.headingDeg),
          accuracyM: last.accuracyM + 250 + 1.5 * secs,
          basis: 'moving with ${labels[buddy.memberId] ?? 'the convoy'}',
        );
      }
    }

    if (last.speedMps < 0.8 && (history[last.memberId]?.length ?? 0) > 1) {
      return last.copyWith(
        source: PositionSource.estimated,
        accuracyM: last.accuracyM + 0.5 * secs,
        basis: 'stopped when last heard',
      );
    }
    final recent = recentSpeed(history[last.memberId] ?? const [], last);
    final road = usable ? roadSpeedAt?.call(onRoute.alongMeters) : null;
    var speed = recent ?? averageSpeed ?? road ?? last.speedMps;
    final speedNote = recent != null
        ? 'recent speed'
        : averageSpeed != null
            ? 'its average speed'
            : road != null
                ? 'typical road speed'
                : 'last speed';
    if (road != null) speed = math.min(speed, road * 1.25);
    if (speed < 0.8) {
      return last.copyWith(
        source: PositionSource.estimated,
        accuracyM: last.accuracyM + 0.5 * secs,
        basis: 'stopped when last heard',
      );
    }

    // 2 + 3. Along the road, pausing at planned stops.
    if (usable) {
      var remaining = secs;
      var along = onRoute.alongMeters;
      String? holdingAt;
      final upcoming = [
        for (final w in stops)
          if (w.plannedDeparture != null) (w, Geo.projectOntoRoute(route, w.location).alongMeters),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (stop, stopAlong) in upcoming) {
        if (stopAlong <= along + 50) continue;
        final travel = (stopAlong - along) / speed;
        if (travel >= remaining) break;
        remaining -= travel;
        along = stopAlong;
        final arrival = last.timestamp.add(Duration(milliseconds: ((secs - remaining) * 1000).round()));
        final dwell = stop.plannedDeparture!.difference(arrival).inMilliseconds / 1000.0;
        if (dwell > 0) {
          final wait = math.min(dwell, const Duration(hours: 2).inSeconds.toDouble());
          if (wait >= remaining) {
            holdingAt = '${stop.name} until ${DateFormat.Hm().format(stop.plannedDeparture!.toLocal())}';
            remaining = 0;
            break;
          }
          remaining -= wait;
        }
      }
      along = (along + speed * remaining).clamp(0, routeLen);
      return last.copyWith(
        point: pointAlong(route, along),
        source: PositionSource.estimated,
        speedMps: holdingAt != null ? 0 : speed,
        headingDeg: _headingAt(route, along, last.headingDeg),
        accuracyM: last.accuracyM + 4 * secs,
        basis: holdingAt != null
            ? 'probably at $holdingAt (planned stop)'
            : along >= routeLen - 1
                ? 'probably at the destination'
                : 'along the road at ~${(speed * 3.6).round()} km/h ($speedNote)',
      );
    }

    // 4. Off route: short straight-line extrapolation only.
    final offSecs = math.min(secs, maxOffRouteProjection.inSeconds.toDouble());
    return last.copyWith(
      point: Geo.destination(last.point, last.headingDeg, speed * offSecs),
      source: PositionSource.estimated,
      accuracyM: last.accuracyM + 8 * secs,
      basis: 'off the planned route; heading ${Geo.compass(last.headingDeg)}',
    );
  }

  /// Smoothed speed over the recent track, or the last reported speed when
  /// there is not enough history.
  static double typicalSpeed(List<VehiclePosition> track, VehiclePosition last) =>
      recentSpeed(track, last) ?? last.speedMps;

  /// Distance covered over time across the last few minutes, blended with
  /// the last reading; null without enough history.
  static double? recentSpeed(List<VehiclePosition> track, VehiclePosition last) {
    final recent = track.where((p) => !p.timestamp.isBefore(last.timestamp.subtract(const Duration(minutes: 5)))).toList();
    if (recent.length < 3) return null;
    var dist = 0.0;
    for (var i = 1; i < recent.length; i++) {
      dist += Geo.distanceMeters(recent[i - 1].point, recent[i].point);
    }
    final dt = recent.last.timestamp.difference(recent.first.timestamp).inMilliseconds / 1000.0;
    if (dt < 30) return null;
    final avg = dist / dt;
    // A car that just stopped: trust the stop. Otherwise blend toward the
    // average so a single slow or fast reading doesn't dominate.
    if (last.speedMps < 0.8) return 0;
    return 0.7 * avg + 0.3 * last.speedMps;
  }

  _Buddy? _buddy(VehiclePosition last, List<GeoPoint> route, Map<String, List<VehiclePosition>> history,
      Map<String, VehiclePosition> latest, DateTime now, double lastAlong) {
    _Buddy? best;
    for (final e in latest.entries) {
      if (e.key == last.memberId || e.value.source == PositionSource.estimated) continue;
      if (now.difference(e.value.timestamp) > freshFor) continue;
      // Where was this car when ours went quiet?
      final track = history[e.key] ?? const <VehiclePosition>[];
      VehiclePosition? then;
      for (final p in track) {
        if ((p.timestamp.difference(last.timestamp)).abs() <= const Duration(seconds: 45)) {
          if (then == null ||
              p.timestamp.difference(last.timestamp).abs() < then.timestamp.difference(last.timestamp).abs()) {
            then = p;
          }
        }
      }
      if (then == null) continue;
      final thenProj = Geo.projectOntoRoute(route, then.point);
      final nowProj = Geo.projectOntoRoute(route, e.value.point);
      if (thenProj.offRouteMeters > 300 || nowProj.offRouteMeters > 300) continue;
      final gap = lastAlong - thenProj.alongMeters;
      if (gap.abs() > buddyMaxGapM) continue;
      if (best == null || gap.abs() < best.gapAtLast.abs()) {
        best = _Buddy(e.key, gap, nowProj.alongMeters, e.value.speedMps);
      }
    }
    return best;
  }

  static double _headingAt(List<GeoPoint> route, double along, double fallback) {
    final a = pointAlong(route, math.max(0, along - 30));
    final b = pointAlong(route, along + 30);
    return Geo.distanceMeters(a, b) < 1 ? fallback : Geo.bearingDeg(a, b);
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

class _Buddy {
  const _Buddy(this.memberId, this.gapAtLast, this.buddyAlongNow, this.buddySpeed);
  final String memberId;
  final double gapAtLast;
  final double buddyAlongNow;
  final double buddySpeed;
}

/// Long-run average *moving* speed of one car (exponentially weighted, so
/// it follows the trip's terrain), persisted with the trip.
class AverageSpeed {
  AverageSpeed([this.value]);

  double? value;
  VehiclePosition? _prev;

  void add(VehiclePosition p) {
    final prev = _prev;
    _prev = p;
    if (prev == null) return;
    final dt = p.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dt < 5 || dt > 600) return;
    final v = Geo.distanceMeters(prev.point, p.point) / dt;
    if (v < 2 || v > 70) return; // stopped, or a GPS jump
    final w = math.min(dt / 600, 0.5);
    value = value == null ? v : value! * (1 - w) + v * w;
  }
}

/// Expected driving speed along the cached road route, per leg (from the
/// routing engine's distance and duration for each leg between stops).
class RoadSpeeds {
  const RoadSpeeds(this.legEnds, this.legSpeeds);

  /// Cumulative distance (m) at the end of each leg, and its speed (m/s).
  final List<double> legEnds;
  final List<double> legSpeeds;

  factory RoadSpeeds.fromLegs(List<({double distanceM, double durationS})> legs) {
    var acc = 0.0;
    final ends = <double>[], speeds = <double>[];
    for (final l in legs) {
      acc += l.distanceM;
      ends.add(acc);
      speeds.add(l.durationS > 0 ? l.distanceM / l.durationS : 0);
    }
    return RoadSpeeds(ends, speeds);
  }

  double? at(double along) {
    for (var i = 0; i < legEnds.length; i++) {
      if (along <= legEnds[i]) return legSpeeds[i] > 0 ? legSpeeds[i] : null;
    }
    return legSpeeds.isEmpty ? null : legSpeeds.last;
  }

  List<List<double>> toJson() => [for (var i = 0; i < legEnds.length; i++) [legEnds[i], legSpeeds[i]]];

  factory RoadSpeeds.fromJson(List<dynamic> j) => RoadSpeeds(
        [for (final e in j) ((e as List)[0] as num).toDouble()],
        [for (final e in j) ((e as List)[1] as num).toDouble()],
      );
}
