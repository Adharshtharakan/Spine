import '../../core/geo/geo.dart';
import '../../data/models/trip.dart';

/// Why a vehicle is shown as the lead.
enum LeadReason {
  /// The organiser designated this vehicle and it is reporting.
  designated,

  /// The designated lead has gone quiet only briefly (a dead zone); it stays
  /// the lead and its position is estimated, so the badge doesn't flip.
  designatedSilent,

  /// The designated lead has gone silent (or none was set), so the vehicle
  /// furthest along the shared route is treated as the de-facto lead.
  furthestAlongRoute,
}

class LeadResult {
  const LeadResult(this.memberId, this.reason, this.alongMeters);

  final String memberId;
  final LeadReason reason;
  final double alongMeters;
}

class ConvoyStanding {
  const ConvoyStanding({
    required this.memberId,
    required this.alongMeters,
    required this.gapToLeadMeters,
    required this.offRouteMeters,
    required this.stale,
  });

  final String memberId;
  final double alongMeters;
  final double gapToLeadMeters;
  final double offRouteMeters;
  final bool stale;

  bool get offRoute => offRouteMeters > 400;
}

/// Identifies the lead vehicle and ranks the convoy along the route.
class LeadVehicleResolver {
  const LeadVehicleResolver({
    this.staleAfter = const Duration(seconds: 90),
    this.holdDesignatedFor = const Duration(minutes: 15),
  });

  final Duration staleAfter;

  /// How long a silent designated lead keeps the role before the front-most
  /// reporting vehicle is shown as lead instead.
  final Duration holdDesignatedFor;

  LeadResult? resolve({
    required String? designatedMemberId,
    required Map<String, VehiclePosition> positions,
    required List<GeoPoint> route,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final fresh = {
      for (final e in positions.entries)
        if (e.value.age(t) <= staleAfter) e.key: e.value,
    };

    double along(VehiclePosition p) =>
        route.length < 2 ? 0 : Geo.projectOntoRoute(route, p.point).alongMeters;

    if (designatedMemberId != null && fresh.containsKey(designatedMemberId)) {
      return LeadResult(designatedMemberId, LeadReason.designated,
          along(fresh[designatedMemberId]!));
    }
    final designated = designatedMemberId == null ? null : positions[designatedMemberId];
    // A short silence (or the whole convoy in a dead zone) keeps the
    // designated lead, so the badge doesn't jump around.
    if (designated != null && (fresh.isEmpty || designated.age(t) <= holdDesignatedFor)) {
      return LeadResult(designatedMemberId!, LeadReason.designatedSilent, along(designated));
    }
    if (fresh.isEmpty) return null;
    String? bestId;
    var best = double.negativeInfinity;
    for (final e in fresh.entries) {
      final a = along(e.value);
      if (a > best) {
        best = a;
        bestId = e.key;
      }
    }
    return LeadResult(bestId!, LeadReason.furthestAlongRoute, best);
  }

  List<ConvoyStanding> standings({
    required LeadResult? lead,
    required Map<String, VehiclePosition> positions,
    required List<GeoPoint> route,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final out = <ConvoyStanding>[];
    for (final e in positions.entries) {
      final proj = route.length < 2
          ? const RouteProjection(0, 0, 0)
          : Geo.projectOntoRoute(route, e.value.point);
      out.add(ConvoyStanding(
        memberId: e.key,
        alongMeters: proj.alongMeters,
        gapToLeadMeters: lead == null ? 0 : (lead.alongMeters - proj.alongMeters),
        offRouteMeters: proj.offRouteMeters,
        stale: e.value.age(t) > staleAfter,
      ));
    }
    out.sort((a, b) => b.alongMeters.compareTo(a.alongMeters));
    return out;
  }
}
