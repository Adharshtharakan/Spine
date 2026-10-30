import 'dart:math' as math;

import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';
import 'lead_vehicle.dart';

enum AlertKind {
  fallingBehind,
  offRoute,
  unplannedStop,
  lostContact,
  planChanged,
  sos,
  hazard,
  regroup,
  headcount,
  fatigue,
  pace,
  fuel,
  sweep,
  weather,
}

class ConvoyAlert {
  const ConvoyAlert({
    required this.kind,
    required this.memberId,
    required this.message,
    required this.at,
    this.spoken,
    this.tag,
  });

  final AlertKind kind;

  /// The vehicle the alert is about (null for plan changes).
  final String? memberId;

  /// Shown on screen.
  final String message;

  /// Read aloud; defaults to [message]. Kept short for drivers.
  final String? spoken;
  final DateTime at;

  /// Distinguishes several alerts of one kind about one member (hazard ids).
  final String? tag;

  String get key => '${kind.name}:${memberId ?? ''}:${tag ?? ''}';
}

/// Watches the convoy and raises the alerts that matter while driving, so
/// nobody has to keep looking at the screen:
///
/// * **falling behind** — a car's gap to the car ahead exceeds what is
///   normal at that speed (≥ 1.5 km, or 90 seconds of travel);
/// * **off route** — more than 500 m off the plan for 45 s while moving;
/// * **unplanned stop** — stopped for 3 min, not near a planned stop;
/// * **lost contact** — nothing heard for 5 min (suppressed while this
///   phone is itself offline, when everyone would look lost, and only for
///   cars that were live during this session).
///
/// Edge-triggered: a condition must hold for its hold time before it fires,
/// fires once, re-arms only after it has cleared, and then respects a
/// cooldown so drivers are informed rather than nagged.
class ConvoyWatch {
  ConvoyWatch({
    this.behindHold = const Duration(seconds: 30),
    this.offRouteHold = const Duration(seconds: 45),
    this.stopHold = const Duration(minutes: 3),
    this.lostAfter = const Duration(minutes: 5),
    this.cooldown = const Duration(minutes: 10),
    this.minGapMeters = 1500,
    this.gapSeconds = 90,
    this.offRouteMeters = 500,
    this.nearStopMeters = 500,
  });

  final Duration behindHold, offRouteHold, stopHold, lostAfter, cooldown;
  final double minGapMeters, gapSeconds, offRouteMeters, nearStopMeters;

  final Map<String, DateTime> _since = {};
  final Map<String, DateTime> _firedAt = {};
  final Set<String> _active = {};
  final Map<String, DateTime> _lastMoving = {};

  /// Cars heard live during this session. Lost contact only applies to
  /// them, so opening a trip days before departure doesn't raise alarms.
  final Set<String> _wasLive = {};

  /// Keys of conditions currently in alert.
  Set<String> get active => Set.unmodifiable(_active);

  /// Returns alerts that became due at [now].
  List<ConvoyAlert> evaluate({
    required DateTime now,
    required Map<String, VehiclePosition> reported,
    required List<ConvoyStanding> standings,
    required List<GeoPoint> route,
    required List<Waypoint> stops,
    required Map<String, String> labels,
    required String? selfId,
    bool selfOnline = true,
  }) {
    final out = <ConvoyAlert>[];
    String name(String id) => id == selfId ? 'You' : (labels[id] ?? 'A car');

    for (final p in reported.values) {
      if (p.speedMps >= 2) _lastMoving[p.memberId] = p.timestamp;
      if (now.difference(p.timestamp) < const Duration(minutes: 2)) _wasLive.add(p.memberId);
    }

    final fresh = standings.where((s) => !s.stale).toList();

    // Falling behind: compare each car with the one directly ahead.
    final behindNow = <String>{};
    if (route.length >= 2) {
      for (var i = 1; i < fresh.length; i++) {
        final ahead = fresh[i - 1], car = fresh[i];
        final speed = reported[ahead.memberId]?.speedMps ?? 0;
        final threshold = math.max(minGapMeters, gapSeconds * speed);
        final gap = ahead.alongMeters - car.alongMeters;
        if (gap > threshold) {
          behindNow.add(car.memberId);
          final msg = car.memberId == selfId
              ? 'You are ${Geo.formatDistance(gap)} behind ${name(ahead.memberId)}'
              : '${name(car.memberId)} is ${Geo.formatDistance(gap)} behind ${name(ahead.memberId)}';
          final spoken = car.memberId == selfId
              ? 'You are falling behind. ${name(ahead.memberId)} is ${_spokenDistance(gap)} ahead.'
              : '${name(car.memberId)} is falling behind, ${_spokenDistance(gap)} back.';
          _check(out, AlertKind.fallingBehind, car.memberId, true, behindHold, now, msg, spoken);
        }
      }
    }
    for (final s in standings) {
      if (!behindNow.contains(s.memberId)) _clear(AlertKind.fallingBehind, s.memberId, now);
    }

    for (final s in standings) {
      final id = s.memberId;
      final p = reported[id];
      if (p == null) continue;

      // Off route (others only: you know where you are).
      final off = id != selfId && !s.stale && route.length >= 2 && s.offRouteMeters > offRouteMeters && p.speedMps > 3;
      final near = _nearestStop(stops, p.point);
      _check(out, AlertKind.offRoute, id, off, offRouteHold, now,
          '${name(id)} has left the route${near == null ? '' : ' near ${near.name}'}',
          '${name(id)} has left the planned route.');

      // Unplanned stop.
      final lastMove = _lastMoving[id];
      final stoppedFor = lastMove == null ? Duration.zero : p.timestamp.difference(lastMove);
      final atPlannedStop = near != null && Geo.distanceMeters(near.location, p.point) <= nearStopMeters;
      final stopped = id != selfId && !s.stale && p.speedMps < 1 && stoppedFor >= stopHold && !atPlannedStop;
      _check(out, AlertKind.unplannedStop, id, stopped, Duration.zero, now,
          '${name(id)} has stopped for ${stoppedFor.inMinutes} min. Not a planned stop.',
          '${name(id)} has stopped. Not a planned stop.');

      // Lost contact.
      final silent = now.difference(p.timestamp);
      final lost = id != selfId && selfOnline && _wasLive.contains(id) && silent >= lostAfter;
      _check(out, AlertKind.lostContact, id, lost, Duration.zero, now,
          'Lost contact with ${name(id)}. Last heard ${silent.inMinutes} min ago',
          'Lost contact with ${name(id)}.');
    }
    return out;
  }

  void _check(List<ConvoyAlert> out, AlertKind kind, String id, bool condition, Duration hold, DateTime now,
      String message, String spoken) {
    final key = '${kind.name}:$id';
    if (!condition) {
      _clear(kind, id, now);
      return;
    }
    final since = _since.putIfAbsent(key, () => now);
    if (_active.contains(key) || now.difference(since) < hold) return;
    final last = _firedAt[key];
    if (last != null && now.difference(last) < cooldown) return;
    _active.add(key);
    _firedAt[key] = now;
    out.add(ConvoyAlert(kind: kind, memberId: id, message: message, spoken: spoken, at: now));
  }

  void _clear(AlertKind kind, String id, DateTime now) {
    final key = '${kind.name}:$id';
    _since.remove(key);
    _active.remove(key);
  }

  static Waypoint? _nearestStop(List<Waypoint> stops, GeoPoint p) {
    Waypoint? best;
    var bestD = double.infinity;
    for (final w in stops) {
      final d = Geo.distanceMeters(w.location, p);
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }

  static String _spokenDistance(double m) =>
      m < 1000 ? '${(m / 100).round() * 100} metres' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} kilometres';

  /// Describes an itinerary change made by someone else, or null when the
  /// change isn't worth interrupting a driver for (notes, ordering).
  static ConvoyAlert? describePlanChange(Waypoint? before, Waypoint after, {required String? by, required DateTime now}) {
    final who = by == null ? '' : '$by: ';
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    String? msg;
    if (before == null && !after.deleted) {
      msg = '${who}new stop ${after.name}${after.plannedArrival != null ? ' at ${hm(after.plannedArrival!)}' : ''}';
    } else if (before != null && !before.deleted && after.deleted) {
      msg = '$who${after.name} removed from the plan';
    } else if (before != null && !after.deleted) {
      final moved = Geo.distanceMeters(before.location, after.location) > 200;
      final retimed = before.plannedArrival != after.plannedArrival || before.plannedDeparture != after.plannedDeparture;
      if (moved) {
        msg = '$who${after.name} moved to a new location';
      } else if (retimed && after.plannedArrival != null) {
        msg = '$who${after.name} now at ${hm(after.plannedArrival!)}';
      } else if (retimed && after.plannedDeparture != null) {
        msg = '${who}leaving ${after.name} at ${hm(after.plannedDeparture!)}';
      } else if (before.name != after.name) {
        msg = '$who${before.name} renamed to ${after.name}';
      }
    }
    if (msg == null) return null;
    final text = 'Plan updated. ${msg[0].toUpperCase()}${msg.substring(1)}';
    return ConvoyAlert(kind: AlertKind.planChanged, memberId: null, message: text, at: now, spoken: 'Plan updated. $msg.');
  }
}
