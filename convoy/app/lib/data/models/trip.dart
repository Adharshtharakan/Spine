import '../../core/geo/geo.dart';

enum TripVisibility { private, public }

enum MemberRole { owner, lead, driver, passenger }

MemberRole memberRoleFromWire(String? s) =>
    MemberRole.values.firstWhere((r) => r.name == s, orElse: () => MemberRole.driver);

class Trip {
  const Trip({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.inviteCode,
    required this.visibility,
    this.leadMemberId,
    this.description = '',
    this.startsAt,
    this.endsAt,
    this.maxVehicles,
    this.publishedAt,
  });

  final String id;
  final String ownerId;
  final String title;
  final String description;
  final String inviteCode;
  final TripVisibility visibility;

  /// `trip_members.id` of the designated lead vehicle.
  final String? leadMemberId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxVehicles;
  final DateTime? publishedAt;

  factory Trip.fromRow(Map<String, dynamic> r) => Trip(
        id: r['id'] as String,
        ownerId: r['owner_id'] as String,
        title: r['title'] as String,
        description: (r['description'] as String?) ?? '',
        inviteCode: (r['invite_code'] as String?) ?? '',
        visibility: r['visibility'] == 'public' ? TripVisibility.public : TripVisibility.private,
        leadMemberId: r['lead_member_id'] as String?,
        startsAt: _d(r['starts_at']),
        endsAt: _d(r['ends_at']),
        maxVehicles: r['max_vehicles'] as int?,
        publishedAt: _d(r['published_at']),
      );

  static DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  Map<String, dynamic> toRow() => {
        'id': id,
        'owner_id': ownerId,
        'title': title,
        'description': description,
        'invite_code': inviteCode,
        'visibility': visibility.name,
        'lead_member_id': leadMemberId,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'max_vehicles': maxVehicles,
        'published_at': publishedAt?.toUtc().toIso8601String(),
      };
}

/// A participant. Every member with a vehicle appears on the convoy map.
class TripMember {
  const TripMember({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.displayName,
    required this.role,
    this.vehicleLabel,
    this.vehicleColor = 0xFF2E7DF6,
    this.hasVehicle = true,
  });

  final String id;
  final String tripId;
  final String userId;
  final String displayName;
  final MemberRole role;
  final String? vehicleLabel;
  final int vehicleColor;
  final bool hasVehicle;

  Map<String, dynamic> toRow() => {
        'id': id,
        'trip_id': tripId,
        'user_id': userId,
        'display_name': displayName,
        'role': role.name,
        'vehicle_label': vehicleLabel,
        'vehicle_color': vehicleColor,
        'has_vehicle': hasVehicle,
      };

  factory TripMember.fromRow(Map<String, dynamic> r) {
    final profile = r['profiles'] as Map<String, dynamic>?;
    return TripMember(
      id: r['id'] as String,
      tripId: r['trip_id'] as String,
      userId: r['user_id'] as String,
      displayName: (profile?['display_name'] as String?) ??
          (r['display_name'] as String?) ??
          'Driver',
      role: memberRoleFromWire(r['role'] as String?),
      vehicleLabel: r['vehicle_label'] as String?,
      vehicleColor: (r['vehicle_color'] as int?)?.toUnsigned(32) ?? 0xFF2E7DF6,
      hasVehicle: (r['has_vehicle'] as bool?) ?? true,
    );
  }
}

/// Where the fix came from — drives how much the map trusts it.
enum PositionSource { cloud, mesh, local, estimated }

class VehiclePosition {
  const VehiclePosition({
    required this.memberId,
    required this.point,
    required this.timestamp,
    this.speedMps = 0,
    this.headingDeg = 0,
    this.accuracyM = 10,
    this.source = PositionSource.cloud,
    this.hops = 0,
    this.basis,
  });

  final String memberId;
  final GeoPoint point;
  final DateTime timestamp;
  final double speedMps;
  final double headingDeg;
  final double accuracyM;
  final PositionSource source;

  /// Mesh relay hops this frame travelled (0 = heard directly).
  final int hops;

  /// For [PositionSource.estimated]: why the app thinks the car is here,
  /// shown to drivers ("moving with Blue Jeep", "at Dhaba until 14:30").
  final String? basis;

  Duration age(DateTime now) => now.difference(timestamp);

  VehiclePosition copyWith({
    GeoPoint? point,
    PositionSource? source,
    double? accuracyM,
    double? speedMps,
    double? headingDeg,
    String? basis,
  }) =>
      VehiclePosition(
        memberId: memberId,
        point: point ?? this.point,
        timestamp: timestamp,
        speedMps: speedMps ?? this.speedMps,
        headingDeg: headingDeg ?? this.headingDeg,
        accuracyM: accuracyM ?? this.accuracyM,
        source: source ?? this.source,
        hops: hops,
        basis: basis ?? this.basis,
      );

  Map<String, dynamic> toJson() => {
        'm': memberId,
        'lat': point.lat,
        'lng': point.lng,
        't': timestamp.toUtc().millisecondsSinceEpoch,
        'v': speedMps,
        'h': headingDeg,
        'a': accuracyM,
      };

  factory VehiclePosition.fromJson(Map<String, dynamic> j,
          {PositionSource source = PositionSource.cloud}) =>
      VehiclePosition(
        memberId: j['m'] as String,
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        timestamp: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt(), isUtc: true),
        speedMps: (j['v'] as num?)?.toDouble() ?? 0,
        headingDeg: (j['h'] as num?)?.toDouble() ?? 0,
        accuracyM: (j['a'] as num?)?.toDouble() ?? 10,
        source: source,
      );
}
