import '../../core/geo/geo.dart';
import '../../services/edge/edge_client.dart';
import '../models/social.dart';

class SponsoredPlacement {
  const SponsoredPlacement({required this.name, required this.partner, required this.category, required this.url, required this.distanceKm});

  final String name;
  final String partner;
  final String category;
  final String url;
  final double distanceKm;

  factory SponsoredPlacement.fromJson(Map<String, dynamic> j) => SponsoredPlacement(
        name: j['name'] as String,
        partner: j['partner_name'] as String,
        category: j['category'] as String,
        url: j['url'] as String,
        distanceKm: (j['distance_km'] as num).toDouble(),
      );
}

class DiscoveryResult {
  const DiscoveryResult(this.trips, this.sponsored);
  final List<PublicTrip> trips;
  final List<SponsoredPlacement> sponsored;
}

/// Public discovery and affiliate offers, served by the Cloudflare Worker.
class EdgeRepository {
  EdgeRepository(this._edge);

  final EdgeClient _edge;

  Future<DiscoveryResult> discover(GeoPoint near, {double radiusKm = 300, List<String> tags = const []}) async {
    final res = await _edge.get('/discovery/trips', {
      'lat': near.lat.toStringAsFixed(4),
      'lng': near.lng.toStringAsFixed(4),
      'radius_km': radiusKm.round().toString(),
      if (tags.isNotEmpty) 'tags': tags.join(','),
    });
    return DiscoveryResult(
      [for (final t in res['trips'] as List) PublicTrip.fromJson(Map<String, dynamic>.from(t as Map))],
      [for (final s in (res['sponsored'] as List? ?? const [])) SponsoredPlacement.fromJson(Map<String, dynamic>.from(s as Map))],
    );
  }

  Future<void> requestToJoin(String tripId, {required String vehicleLabel, String message = ''}) =>
      _edge.post('/discovery/trips/$tripId/join', {'vehicle_label': vehicleLabel, 'message': message});

  Future<List<AffiliateOffer>> offersAlongRoute(List<GeoPoint> route,
      {Set<OfferCategory>? categories, String? tripId}) async {
    final res = await _edge.post('/affiliates/along-route', {
      'route': [for (final p in route) [p.lat, p.lng]],
      if (categories != null)
        'categories': [
          for (final c in categories)
            switch (c) {
              OfferCategory.hotel => 'hotel',
              OfferCategory.campsite => 'campsite',
              OfferCategory.fuel => 'fuel',
              OfferCategory.restArea => 'rest_area',
            },
        ],
      'trip_id': ?tripId,
    });
    return [for (final o in res['offers'] as List) AffiliateOffer.fromJson(Map<String, dynamic>.from(o as Map))];
  }
}
