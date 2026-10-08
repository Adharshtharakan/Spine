import '../../core/geo/geo.dart';

enum WaypointKind {
  origin,
  waypoint,
  restStop,
  fuel,
  lodging,
  campsite,
  destination;

  String get wire => switch (this) {
        WaypointKind.restStop => 'rest_stop',
        _ => name,
      };

  static WaypointKind fromWire(String s) => switch (s) {
        'rest_stop' => WaypointKind.restStop,
        _ => WaypointKind.values.firstWhere((k) => k.name == s,
            orElse: () => WaypointKind.waypoint),
      };

  String get label => switch (this) {
        WaypointKind.origin => 'Start',
        WaypointKind.waypoint => 'Waypoint',
        WaypointKind.restStop => 'Rest stop',
        WaypointKind.fuel => 'Fuel',
        WaypointKind.lodging => 'Lodging',
        WaypointKind.campsite => 'Campsite',
        WaypointKind.destination => 'Destination',
      };
}

/// One stop on the shared roadmap. Every field edit carries the HLC of the
/// write; the row with the greater [hlc] wins on both client and server.
class Waypoint {
  const Waypoint({
    required this.id,
    required this.tripId,
    required this.name,
    required this.location,
    required this.kind,
    required this.sortKey,
    required this.hlc,
    this.plannedArrival,
    this.plannedDeparture,
    this.notes = '',
    this.deleted = false,
    this.updatedBy,
    this.affiliateOfferId,
  });

  final String id;
  final String tripId;
  final String name;
  final GeoPoint location;
  final WaypointKind kind;

  /// Fractional index: ordering is by [sortKey] then [id], so concurrent
  /// inserts between the same pair never collide on a renumbering.
  final double sortKey;
  final String hlc;
  final DateTime? plannedArrival;
  final DateTime? plannedDeparture;
  final String notes;
  final bool deleted;
  final String? updatedBy;
  final String? affiliateOfferId;

  Waypoint copyWith({
    String? name,
    GeoPoint? location,
    WaypointKind? kind,
    double? sortKey,
    String? hlc,
    DateTime? plannedArrival,
    DateTime? plannedDeparture,
    bool clearArrival = false,
    bool clearDeparture = false,
    String? notes,
    bool? deleted,
    String? updatedBy,
  }) =>
      Waypoint(
        id: id,
        tripId: tripId,
        name: name ?? this.name,
        location: location ?? this.location,
        kind: kind ?? this.kind,
        sortKey: sortKey ?? this.sortKey,
        hlc: hlc ?? this.hlc,
        plannedArrival: clearArrival ? null : plannedArrival ?? this.plannedArrival,
        plannedDeparture:
            clearDeparture ? null : plannedDeparture ?? this.plannedDeparture,
        notes: notes ?? this.notes,
        deleted: deleted ?? this.deleted,
        updatedBy: updatedBy ?? this.updatedBy,
        affiliateOfferId: affiliateOfferId,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'trip_id': tripId,
        'name': name,
        'lat': location.lat,
        'lng': location.lng,
        'kind': kind.wire,
        'sort_key': sortKey,
        'hlc': hlc,
        'planned_arrival': plannedArrival?.toUtc().toIso8601String(),
        'planned_departure': plannedDeparture?.toUtc().toIso8601String(),
        'notes': notes,
        'deleted': deleted,
        'updated_by': updatedBy,
        'affiliate_offer_id': affiliateOfferId,
      };

  factory Waypoint.fromRow(Map<String, dynamic> r) => Waypoint(
        id: r['id'] as String,
        tripId: r['trip_id'] as String,
        name: (r['name'] as String?) ?? '',
        location: GeoPoint((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
        kind: WaypointKind.fromWire((r['kind'] as String?) ?? 'waypoint'),
        sortKey: (r['sort_key'] as num).toDouble(),
        hlc: r['hlc'] as String,
        plannedArrival: _date(r['planned_arrival']),
        plannedDeparture: _date(r['planned_departure']),
        notes: (r['notes'] as String?) ?? '',
        deleted: (r['deleted'] as bool?) ?? false,
        updatedBy: r['updated_by'] as String?,
        affiliateOfferId: r['affiliate_offer_id'] as String?,
      );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
