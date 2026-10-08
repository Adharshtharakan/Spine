import '../../core/geo/geo.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.senderName,
    this.kind = 'text',
    this.pending = false,
    this.viaMesh = false,
  });

  final String id;
  final String tripId;
  final String senderId;
  final String? senderName;
  final String body;

  /// `text`, `system` (joins, lead changes, schedule shifts) or `quick`
  /// (one-tap canned messages that are safe to send while driving).
  final String kind;
  final DateTime createdAt;
  final bool pending;
  final bool viaMesh;

  Map<String, dynamic> toRow() => {
        'id': id,
        'trip_id': tripId,
        'sender_id': senderId,
        'body': body,
        'kind': kind,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ChatMessage.fromRow(Map<String, dynamic> r) => ChatMessage(
        id: r['id'] as String,
        tripId: r['trip_id'] as String,
        senderId: r['sender_id'] as String,
        senderName: (r['profiles'] as Map<String, dynamic>?)?['display_name'] as String?,
        body: r['body'] as String,
        kind: (r['kind'] as String?) ?? 'text',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );

  ChatMessage copyWith({bool? pending, bool? viaMesh}) => ChatMessage(
        id: id,
        tripId: tripId,
        senderId: senderId,
        senderName: senderName,
        body: body,
        kind: kind,
        createdAt: createdAt,
        pending: pending ?? this.pending,
        viaMesh: viaMesh ?? this.viaMesh,
      );
}

class GuidelineDocument {
  const GuidelineDocument({
    required this.id,
    required this.kind,
    required this.version,
    required this.title,
    required this.body,
  });

  final String id;

  /// `platform_guidelines` or `driver_terms`.
  final String kind;
  final int version;
  final String title;
  final String body;

  factory GuidelineDocument.fromRow(Map<String, dynamic> r) => GuidelineDocument(
        id: r['id'] as String,
        kind: r['kind'] as String,
        version: r['version'] as int,
        title: r['title'] as String,
        body: r['body'] as String,
      );
}

class PublicTrip {
  const PublicTrip({
    required this.id,
    required this.title,
    required this.summary,
    required this.ownerName,
    required this.ownerVerified,
    required this.start,
    required this.end,
    required this.vehicleCount,
    required this.openSlots,
    this.startsAt,
    this.tags = const [],
    this.distanceKm,
    this.sponsored = false,
  });

  final String id;
  final String title;
  final String summary;
  final String ownerName;
  final bool ownerVerified;
  final GeoPoint start;
  final GeoPoint end;
  final int vehicleCount;
  final int openSlots;
  final DateTime? startsAt;
  final List<String> tags;
  final double? distanceKm;
  final bool sponsored;

  factory PublicTrip.fromJson(Map<String, dynamic> j) => PublicTrip(
        id: j['id'] as String,
        title: j['title'] as String,
        summary: (j['summary'] as String?) ?? '',
        ownerName: (j['owner_name'] as String?) ?? 'Organiser',
        ownerVerified: (j['owner_verified'] as bool?) ?? false,
        start: GeoPoint((j['start_lat'] as num).toDouble(), (j['start_lng'] as num).toDouble()),
        end: GeoPoint((j['end_lat'] as num).toDouble(), (j['end_lng'] as num).toDouble()),
        vehicleCount: (j['vehicle_count'] as num?)?.toInt() ?? 0,
        openSlots: (j['open_slots'] as num?)?.toInt() ?? 0,
        startsAt: j['starts_at'] == null ? null : DateTime.parse(j['starts_at'] as String).toLocal(),
        tags: ((j['tags'] as List?) ?? const []).cast<String>(),
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        sponsored: (j['sponsored'] as bool?) ?? false,
      );
}

enum JoinRequestStatus { pending, approved, declined, withdrawn }

class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.tripId,
    required this.requesterId,
    required this.requesterName,
    required this.status,
    required this.vehicleLabel,
    required this.message,
    required this.requesterAcceptedTerms,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String requesterId;
  final String requesterName;
  final JoinRequestStatus status;
  final String vehicleLabel;
  final String message;
  final bool requesterAcceptedTerms;
  final DateTime createdAt;

  factory JoinRequest.fromRow(Map<String, dynamic> r) => JoinRequest(
        id: r['id'] as String,
        tripId: r['trip_id'] as String,
        requesterId: r['requester_id'] as String,
        requesterName:
            (r['profiles'] as Map<String, dynamic>?)?['display_name'] as String? ?? 'Traveller',
        status: JoinRequestStatus.values.firstWhere((s) => s.name == r['status'],
            orElse: () => JoinRequestStatus.pending),
        vehicleLabel: (r['vehicle_label'] as String?) ?? '',
        message: (r['message'] as String?) ?? '',
        requesterAcceptedTerms: r['requester_guidelines_version'] != null &&
            r['requester_terms_version'] != null,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}

enum OfferCategory { hotel, campsite, fuel, restArea }

class AffiliateOffer {
  const AffiliateOffer({
    required this.id,
    required this.category,
    required this.name,
    required this.location,
    required this.provider,
    required this.detourKm,
    this.alongKm,
    this.priceHint,
    this.rating,
    this.bookingUrl,
    this.sponsored = false,
    this.brand,
  });

  final String id;
  final OfferCategory category;
  final String name;
  final GeoPoint location;
  final String provider;
  final double detourKm;
  final double? alongKm;
  final String? priceHint;
  final double? rating;

  /// Worker-signed redirect (`/affiliates/click?...`). Tapping it records the
  /// click for commission attribution before forwarding to the partner.
  final String? bookingUrl;
  final bool sponsored;
  final String? brand;

  static OfferCategory _cat(String s) => switch (s) {
        'hotel' => OfferCategory.hotel,
        'campsite' => OfferCategory.campsite,
        'fuel' => OfferCategory.fuel,
        _ => OfferCategory.restArea,
      };

  factory AffiliateOffer.fromJson(Map<String, dynamic> j) => AffiliateOffer(
        id: j['id'] as String,
        category: _cat(j['category'] as String),
        name: j['name'] as String,
        location: GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        provider: j['provider'] as String,
        detourKm: (j['detour_km'] as num?)?.toDouble() ?? 0,
        alongKm: (j['along_km'] as num?)?.toDouble(),
        priceHint: j['price_hint'] as String?,
        rating: (j['rating'] as num?)?.toDouble(),
        bookingUrl: j['booking_url'] as String?,
        sponsored: (j['sponsored'] as bool?) ?? false,
        brand: j['brand'] as String?,
      );
}

enum Tier { free, premium }

/// What the current user is allowed to do. Mirrors `entitlements` and the
/// limits enforced server-side; the client only uses it to explain limits
/// before the server refuses.
class Entitlement {
  const Entitlement({required this.tier, this.expiresAt});

  final Tier tier;
  final DateTime? expiresAt;

  static const int freeVehicleCap = 2;
  static const int premiumVehicleCap = 25;
  static const double freeOfflineAreaKm2 = 2500;
  static const int freeOfflineRegions = 1;

  bool get isPremium =>
      tier == Tier.premium && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  int get vehicleCap => isPremium ? premiumVehicleCap : freeVehicleCap;

  /// Advanced offline tools: route-corridor packs, mesh relaying beyond one
  /// hop, dead-reckoning for silent vehicles.
  bool get advancedOffline => isPremium;

  static const free = Entitlement(tier: Tier.free);
}
