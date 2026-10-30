import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../data/models/convoy_event.dart';
import '../../data/models/trip.dart';
import 'convoy_watch.dart';
import 'lead_vehicle.dart';

/// Gentle nudges for this driver: a break after two hours at the wheel, and
/// easing off when far over the convoy's pace. Spoken, never nagging: each
/// repeats only after a cooldown.
class DriverNudges {
  DriverNudges({
    this.breakAfter = const Duration(hours: 2),
    this.breakRepeat = const Duration(minutes: 30),
    this.restCounts = const Duration(minutes: 10),
    this.paceMarginKmh = 25,
    this.paceHold = const Duration(seconds: 60),
    this.paceCooldown = const Duration(minutes: 10),
  });

  final Duration breakAfter, breakRepeat, restCounts, paceHold, paceCooldown;
  final double paceMarginKmh;

  DateTime? _drivingSince;
  DateTime? _slowSince;
  DateTime? _lastBreakNudge;
  DateTime? _fastSince;
  DateTime? _lastPaceNudge;

  /// How long this driver has been driving without a real break.
  Duration drivingFor(DateTime now) => _drivingSince == null ? Duration.zero : now.difference(_drivingSince!);

  /// [me] is this phone's latest fix; [convoyKmh] the median speed of the
  /// other moving cars (null when nobody else is moving).
  List<ConvoyAlert> evaluate({required DateTime now, required VehiclePosition? me, double? convoyKmh}) {
    final out = <ConvoyAlert>[];
    if (me == null || now.difference(me.timestamp) > const Duration(minutes: 2)) return out;
    final kmh = me.speedMps * 3.6;

    // Driving time: a stop of [restCounts] or more resets it.
    if (kmh >= 10) {
      _slowSince = null;
      _drivingSince ??= now;
    } else if (kmh < 5) {
      _slowSince ??= now;
      if (now.difference(_slowSince!) >= restCounts) {
        _drivingSince = null;
        _lastBreakNudge = null;
      }
    }
    final driving = drivingFor(now);
    if (driving >= breakAfter && (_lastBreakNudge == null || now.difference(_lastBreakNudge!) >= breakRepeat)) {
      _lastBreakNudge = now;
      final h = driving.inMinutes ~/ 60, m = driving.inMinutes % 60;
      final span = m == 0 ? '$h hours' : '$h hours $m minutes';
      out.add(ConvoyAlert(
        kind: AlertKind.fatigue,
        memberId: me.memberId,
        message: 'You have been driving for $span. Time for a short break?',
        spoken: 'You have been driving for $span. Consider a short break at the next safe place.',
        at: now,
      ));
    }

    // Pace: well above the convoy, held for a minute.
    final fast = convoyKmh != null && kmh >= 60 && kmh > convoyKmh + paceMarginKmh;
    if (!fast) {
      _fastSince = null;
    } else {
      _fastSince ??= now;
      if (now.difference(_fastSince!) >= paceHold &&
          (_lastPaceNudge == null || now.difference(_lastPaceNudge!) >= paceCooldown)) {
        _lastPaceNudge = now;
        out.add(ConvoyAlert(
          kind: AlertKind.pace,
          memberId: me.memberId,
          message: 'You are ${(kmh - convoyKmh).round()} km/h faster than the convoy. Easing off keeps the group together.',
          spoken: 'You are well ahead of the convoy pace. Consider easing off.',
          at: now,
        ));
      }
    }
    return out;
  }
}

/// For the sweep car: anyone behind it is a straggler the sweep should know
/// about. Raised after 30 s, once per car per 10 minutes.
class SweepWatch {
  SweepWatch({this.marginMeters = 300, this.hold = const Duration(seconds: 30), this.cooldown = const Duration(minutes: 10)});

  final double marginMeters;
  final Duration hold, cooldown;
  final Map<String, DateTime> _since = {};
  final Map<String, DateTime> _fired = {};

  List<ConvoyAlert> evaluate({
    required DateTime now,
    required String? sweepId,
    required List<ConvoyStanding> standings,
    required Map<String, String> labels,
  }) {
    final out = <ConvoyAlert>[];
    final sweep = standings.where((s) => s.memberId == sweepId).firstOrNull;
    if (sweep == null || sweep.stale) {
      _since.clear();
      return out;
    }
    for (final s in standings) {
      if (s.memberId == sweepId || s.stale) continue;
      final behind = sweep.alongMeters - s.alongMeters;
      if (behind < marginMeters) {
        _since.remove(s.memberId);
        continue;
      }
      final since = _since.putIfAbsent(s.memberId, () => now);
      final fired = _fired[s.memberId];
      if (now.difference(since) >= hold && (fired == null || now.difference(fired) >= cooldown)) {
        _fired[s.memberId] = now;
        final name = labels[s.memberId] ?? 'A car';
        out.add(ConvoyAlert(
          kind: AlertKind.sweep,
          memberId: s.memberId,
          message: '$name is behind you, ${Geo.formatDistance(behind)} back.',
          spoken: '$name is behind you. You are the sweep car.',
          at: now,
        ));
      }
    }
    return out;
  }
}

/// Announces hazard reports to cars that are approaching them: once per
/// hazard, when it is within [warnMeters] ahead along the route (or simply
/// that close, off the planned route).
class HazardAhead {
  HazardAhead({this.warnMeters = 2000, this.onRouteMeters = 150});

  final double warnMeters, onRouteMeters;
  final Set<String> _announced = {};

  List<ConvoyAlert> evaluate({
    required DateTime now,
    required VehiclePosition? me,
    required List<ConvoyEvent> hazards,
    required List<GeoPoint> route,
  }) {
    final out = <ConvoyAlert>[];
    if (me == null) return out;
    final myAlong = route.length >= 2 ? Geo.projectOntoRoute(route, me.point) : null;
    for (final h in hazards) {
      final at = h.location;
      if (at == null || _announced.contains(h.id) || h.memberId == me.memberId) continue;
      double? ahead;
      if (myAlong != null && myAlong.offRouteMeters < 500) {
        final p = Geo.projectOntoRoute(route, at);
        if (p.offRouteMeters <= onRouteMeters) {
          final d = p.alongMeters - myAlong.alongMeters;
          if (d >= 0 && d <= warnMeters) ahead = d;
        }
      } else {
        final d = Geo.distanceMeters(me.point, at);
        // Off the plan: only if it lies roughly where we are heading.
        final turn = ((Geo.bearingDeg(me.point, at) - me.headingDeg + 540) % 360 - 180).abs();
        if (d <= warnMeters && (me.speedMps < 2 || turn < 60)) ahead = d;
      }
      if (ahead == null) continue;
      _announced.add(h.id);
      final what = h.hazard.label;
      out.add(ConvoyAlert(
        kind: AlertKind.hazard,
        memberId: h.memberId,
        tag: h.id,
        message: '$what reported ${Geo.formatDistance(ahead)} ahead.',
        spoken: '$what reported ${_spoken(ahead)} ahead.',
        at: now,
      ));
    }
    return out;
  }

  static String _spoken(double m) =>
      m < 1000 ? '${(m / 100).round() * 100} metres' : '${(m / 1000).toStringAsFixed(1)} kilometres';
}

/// How far and how long each car is from the regroup point.
class RegroupEta {
  const RegroupEta({required this.memberId, required this.distanceMeters, required this.eta, required this.arrived});

  final String memberId;
  final double distanceMeters;

  /// Null when the car is not moving and has no known average speed.
  final Duration? eta;
  final bool arrived;

  static const arrivedWithinMeters = 150.0;

  /// Road distance along [route] when both are on it, otherwise straight-line
  /// distance with a typical road detour factor.
  static List<RegroupEta> compute({
    required GeoPoint point,
    required Map<String, VehiclePosition> positions,
    required List<GeoPoint> route,
    Map<String, double?> averageSpeedMps = const {},
  }) {
    final pin = route.length >= 2 ? Geo.projectOntoRoute(route, point) : null;
    final out = <RegroupEta>[];
    for (final p in positions.values) {
      final straight = Geo.distanceMeters(p.point, point);
      var d = straight * 1.3;
      if (pin != null && pin.offRouteMeters < 300) {
        final car = Geo.projectOntoRoute(route, p.point);
        if (car.offRouteMeters < 300) d = (pin.alongMeters - car.alongMeters).abs();
      }
      final arrived = straight <= arrivedWithinMeters;
      final speed = math.max(p.speedMps, averageSpeedMps[p.memberId] ?? 0);
      out.add(RegroupEta(
        memberId: p.memberId,
        distanceMeters: arrived ? 0 : d,
        eta: arrived ? Duration.zero : speed > 1.5 ? Duration(seconds: (d / speed).round()) : null,
        arrived: arrived,
      ));
    }
    out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return out;
  }
}

/// "Next fuel in 140 km, your range is 90 km."
class FuelStatus {
  const FuelStatus({required this.rangeKm, required this.nextFuelKm, required this.nextFuelName, required this.warn});

  final double rangeKm;

  /// Distance along the route to the next planned fuel stop (null: none ahead).
  final double? nextFuelKm;
  final String? nextFuelName;

  /// Range will not comfortably reach the next fuel (or the destination when
  /// no fuel stop is planned).
  final bool warn;

  static const bufferKm = 20.0;

  static FuelStatus evaluate({
    required double rangeKm,
    required double myAlongKm,
    required List<({String name, double alongKm})> fuelStops,
    required double routeKm,
  }) {
    final next = fuelStops.where((f) => f.alongKm > myAlongKm + 0.3).toList()..sort((a, b) => a.alongKm.compareTo(b.alongKm));
    final to = next.isEmpty ? null : next.first.alongKm - myAlongKm;
    final needed = to ?? math.max(0, routeKm - myAlongKm);
    return FuelStatus(
      rangeKm: rangeKm,
      nextFuelKm: to,
      nextFuelName: next.isEmpty ? null : next.first.name,
      warn: rangeKm < needed + bufferKm,
    );
  }
}

/// Fuel and toll estimate for one car over the route.
class TripCost {
  const TripCost({required this.distanceKm, required this.fuelLitres, required this.fuelCost, required this.tollCost, required this.plazas});

  final double distanceKm;
  final double? fuelLitres;
  final double? fuelCost;
  final double? tollCost;
  final int plazas;

  double? get total => fuelCost == null && tollCost == null ? null : (fuelCost ?? 0) + (tollCost ?? 0);

  static TripCost estimate({
    required double distanceKm,
    double? kmpl,
    double? fuelPrice,
    required int plazas,
    double? tollPerPlaza,
  }) {
    final litres = kmpl == null || kmpl <= 0 ? null : distanceKm / kmpl;
    return TripCost(
      distanceKm: distanceKm,
      fuelLitres: litres,
      fuelCost: litres == null || fuelPrice == null ? null : litres * fuelPrice,
      tollCost: tollPerPlaza == null ? null : plazas * tollPerPlaza,
      plazas: plazas,
    );
  }
}
