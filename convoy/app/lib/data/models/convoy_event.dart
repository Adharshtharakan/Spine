import '../../core/geo/geo.dart';

/// Something a member raises for the whole convoy. Append-only: current
/// state (who needs help, live hazards, the regroup point, who is ready) is
/// derived from the sequence by [ConvoyEventState].
enum EventKind {
  sos,
  sosClear,
  hazard,
  hazardClear,
  regroup,
  regroupClear,
  headcount,
  ready,
  go;

  String get wire => switch (this) {
        EventKind.sosClear => 'sos_clear',
        EventKind.hazardClear => 'hazard_clear',
        EventKind.regroupClear => 'regroup_clear',
        _ => name,
      };

  static EventKind? fromWire(String? s) => switch (s) {
        'sos_clear' => EventKind.sosClear,
        'hazard_clear' => EventKind.hazardClear,
        'regroup_clear' => EventKind.regroupClear,
        _ => EventKind.values.where((k) => k.name == s).firstOrNull,
      };
}

enum HazardType {
  pothole,
  police,
  accident,
  flood;

  String get label => switch (this) {
        HazardType.pothole => 'Pothole',
        HazardType.police => 'Police',
        HazardType.accident => 'Accident',
        HazardType.flood => 'Flooded road',
      };

  /// How long a report stays on the map unless someone clears it.
  Duration get lifetime => switch (this) {
        HazardType.pothole => const Duration(days: 3),
        HazardType.flood => const Duration(hours: 6),
        HazardType.accident => const Duration(hours: 2),
        HazardType.police => const Duration(hours: 1),
      };

  static HazardType fromWire(String? s) => HazardType.values.firstWhere((h) => h.name == s, orElse: () => HazardType.pothole);
}

class ConvoyEvent {
  const ConvoyEvent({
    required this.id,
    required this.tripId,
    required this.memberId,
    required this.kind,
    required this.createdAt,
    this.location,
    this.payload = const {},
    this.viaMesh = false,
  });

  final String id;
  final String tripId;

  /// The member the event is about / raised by.
  final String memberId;
  final EventKind kind;
  final GeoPoint? location;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool viaMesh;

  /// The event this one refers to (a clear names the SOS/hazard/regroup it ends).
  String? get ref => payload['ref'] as String?;

  HazardType get hazard => HazardType.fromWire(payload['type'] as String?);

  /// Free text: a regroup point's name, an SOS reason.
  String? get note => payload['note'] as String?;

  Map<String, dynamic> toRow() => {
        'id': id,
        'trip_id': tripId,
        'member_id': memberId,
        'kind': kind.wire,
        if (location != null) 'lat': location!.lat,
        if (location != null) 'lng': location!.lng,
        'payload': payload,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static ConvoyEvent? fromRow(Map<String, dynamic> r, {bool viaMesh = false}) {
    final kind = EventKind.fromWire(r['kind'] as String?);
    if (kind == null) return null;
    final lat = (r['lat'] as num?)?.toDouble();
    final lng = (r['lng'] as num?)?.toDouble();
    return ConvoyEvent(
      id: r['id'] as String,
      tripId: r['trip_id'] as String,
      memberId: r['member_id'] as String,
      kind: kind,
      location: lat == null || lng == null ? null : GeoPoint(lat, lng),
      payload: r['payload'] is Map ? Map<String, dynamic>.from(r['payload'] as Map) : const {},
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      viaMesh: viaMesh,
    );
  }
}

/// A shared or personal checklist entry.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.tripId,
    required this.category,
    required this.title,
    this.memberId,
    this.done = false,
    this.sort = 0,
  });

  final String id;
  final String tripId;

  /// Null: shared with the party. Otherwise personal.
  final String? memberId;

  /// `documents`, `vehicle`, `packing` or `group`.
  final String category;
  final String title;
  final bool done;
  final double sort;

  ChecklistItem copyWith({bool? done}) =>
      ChecklistItem(id: id, tripId: tripId, memberId: memberId, category: category, title: title, done: done ?? this.done, sort: sort);

  Map<String, dynamic> toRow() => {
        'id': id,
        'trip_id': tripId,
        'member_id': memberId,
        'category': category,
        'title': title,
        'done': done,
        'sort': sort,
      };

  factory ChecklistItem.fromRow(Map<String, dynamic> r) => ChecklistItem(
        id: r['id'] as String,
        tripId: r['trip_id'] as String,
        memberId: r['member_id'] as String?,
        category: r['category'] as String,
        title: r['title'] as String,
        done: (r['done'] as bool?) ?? false,
        sort: (r['sort'] as num?)?.toDouble() ?? 0,
      );
}
