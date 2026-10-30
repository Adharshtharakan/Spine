// Renders the app's real screens with sample data to PNGs, for design
// review without a device or backend:
//
//   flutter test test_preview --dart-define=PREVIEW_OUT=/some/dir
//
// Lives outside test/ so CI never runs it. The live MapLibre view cannot
// render in a test, so map screens paint an illustrative backdrop behind the
// real overlays, drawing the route, stops and vehicles the way ConvoyMap
// styles them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:convoy/core/geo/geo.dart';
import 'package:convoy/core/theme/theme.dart';
import 'package:convoy/core/theme/tokens.dart';
import 'package:convoy/core/widgets/one_ui.dart';
import 'package:convoy/data/models/social.dart';
import 'package:convoy/data/models/trip.dart';
import 'package:convoy/data/models/waypoint.dart';
import 'package:convoy/data/repositories/edge_repository.dart';
import 'package:convoy/data/repositories/trip_repository.dart';
import 'package:convoy/features/auth/sign_in_screen.dart';
import 'package:convoy/features/chat/chat_tab.dart';
import 'package:convoy/features/discovery/discover_screen.dart';
import 'package:convoy/features/guidelines/guidelines_screen.dart';
import 'package:convoy/features/itinerary/itinerary_tab.dart';
import 'package:convoy/features/map/map_tab.dart';
import 'package:convoy/features/offline_maps/offline_maps_screen.dart';
import 'package:convoy/features/paywall/paywall_screen.dart';
import 'package:convoy/features/radio/radio_screen.dart';
import 'package:convoy/features/stops/stops_tab.dart';
import 'package:convoy/features/trips/convoy_tab.dart';
import 'package:convoy/features/trips/home_screen.dart';
import 'package:convoy/services/edge/edge_client.dart';
import 'package:convoy/services/tracking/convoy_watch.dart';
import 'package:convoy/services/tracking/lead_vehicle.dart';
import 'package:convoy/services/tracking/predictor.dart';
import 'package:convoy/services/voice/ptt_service.dart';
import 'package:convoy/state/providers.dart';
import 'package:convoy/state/trip_session.dart';
import 'package:convoy/sync/itinerary_doc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show InAppPurchase;
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _out = String.fromEnvironment('PREVIEW_OUT', defaultValue: 'build/previews');
const _logical = Size(412, 892);
const _dpr = 2.625;

// ───────────────────────────── sample data ─────────────────────────────

const tripId = '7cba5322-6ff2-40c6-9a10-5720dc911c3c';
const mAngith = '11111111-0000-4000-8000-000000000001';
const mRavi = '22222222-0000-4000-8000-000000000002';
const mPriya = '33333333-0000-4000-8000-000000000003';
const mArjun = '44444444-0000-4000-8000-000000000004';
const mKavya = '55555555-0000-4000-8000-000000000005';
const uAngith = 'aaaaaaaa-0000-4000-8000-00000000000a';

final now = DateTime.now();
DateTime today(int h, int m) => DateTime(now.year, now.month, now.day, h, m);

final members = {
  mAngith: const TripMember(id: mAngith, tripId: tripId, userId: uAngith, displayName: 'Angith', role: MemberRole.owner, vehicleLabel: 'Swift', vehicleColor: 0xFFE5484D),
  mRavi: const TripMember(id: mRavi, tripId: tripId, userId: 'u2', displayName: 'Ravi', role: MemberRole.lead, vehicleLabel: 'Innova', vehicleColor: 0xFF2E7DF6),
  mPriya: const TripMember(id: mPriya, tripId: tripId, userId: 'u3', displayName: 'Priya', role: MemberRole.driver, vehicleLabel: 'Thar', vehicleColor: 0xFF30A46C),
  mArjun: const TripMember(id: mArjun, tripId: tripId, userId: 'u4', displayName: 'Arjun', role: MemberRole.driver, vehicleLabel: 'Ertiga', vehicleColor: 0xFF8E4EC6),
  mKavya: const TripMember(id: mKavya, tripId: tripId, userId: 'u5', displayName: 'Kavya', role: MemberRole.passenger, hasVehicle: false),
};

final trip = Trip(
  id: tripId,
  ownerId: uAngith,
  title: 'Coorg weekend',
  inviteCode: 'K7Q2M9XP',
  visibility: TripVisibility.public,
  leadMemberId: mRavi,
  startsAt: today(7, 0),
);

/// Bengaluru → Mysuru → Madikeri, with a gentle wiggle so it reads as a road.
final List<GeoPoint> road = () {
  const towns = [
    GeoPoint(12.9716, 77.5946), GeoPoint(12.9177, 77.4838), GeoPoint(12.7966, 77.3866),
    GeoPoint(12.7209, 77.2799), GeoPoint(12.6518, 77.2089), GeoPoint(12.5843, 77.0430),
    GeoPoint(12.5218, 76.8951), GeoPoint(12.4216, 76.6936), GeoPoint(12.2958, 76.6394),
    GeoPoint(12.3093, 76.2905), GeoPoint(12.3367, 76.0992), GeoPoint(12.4577, 75.9586),
    GeoPoint(12.4244, 75.7382),
  ];
  final out = <GeoPoint>[];
  for (var i = 0; i < towns.length - 1; i++) {
    final a = towns[i], b = towns[i + 1];
    for (var k = 0; k < 40; k++) {
      final t = k / 40;
      final wig = math.sin(t * math.pi * 3 + i) * 0.004 * math.sin(t * math.pi);
      out.add(GeoPoint(a.lat + (b.lat - a.lat) * t + wig, a.lng + (b.lng - a.lng) * t - wig));
    }
  }
  out.add(towns.last);
  return out;
}();

final itinerary = ItineraryDoc(tripId, nodeId: 'prev')
  ..mergeAll([
    Waypoint(id: 'w1', tripId: tripId, name: 'Start: Indiranagar', location: road.first, kind: WaypointKind.origin, sortKey: 1, hlc: '000000000000001-00000-prev', plannedDeparture: today(7, 0)),
    Waypoint(id: 'w2', tripId: tripId, name: 'Kamat Lokaruchi, Bidadi', location: road[80], kind: WaypointKind.restStop, sortKey: 2, hlc: '000000000000001-00000-prev', plannedArrival: today(8, 10), plannedDeparture: today(8, 40), notes: 'Breakfast'),
    Waypoint(id: 'w3', tripId: tripId, name: 'HP Petrol, Maddur', location: road[200], kind: WaypointKind.fuel, sortKey: 3, hlc: '000000000000001-00000-prev', plannedArrival: today(9, 20)),
    Waypoint(id: 'w4', tripId: tripId, name: 'Lunch: Mysuru', location: road[320], kind: WaypointKind.restStop, sortKey: 4, hlc: '000000000000001-00000-prev', plannedArrival: today(11, 30), plannedDeparture: today(12, 30)),
    Waypoint(id: 'w5', tripId: tripId, name: 'Riverside camp, Dubare', location: road[440], kind: WaypointKind.campsite, sortKey: 5, hlc: '000000000000001-00000-prev', plannedArrival: today(14, 15)),
    Waypoint(id: 'w6', tripId: tripId, name: 'Madikeri homestay', location: road.last, kind: WaypointKind.destination, sortKey: 6, hlc: '000000000000001-00000-prev', plannedArrival: today(15, 30)),
  ]);

final routeLen = Geo.routeLength(road);
final leadAlong = Geo.projectOntoRoute(road, road[200]).alongMeters + 14000;

/// A car's recent track: a fix every 10 s for 15 min at [speed], ending at
/// [endAlong] at time [end].
List<VehiclePosition> track(String id, double endAlong, DateTime end, {double speed = 22, double accuracy = 6}) => [
      for (var s = 900; s >= 0; s -= 10)
        VehiclePosition(
          memberId: id,
          point: ConvoyPredictor.pointAlong(road, endAlong - speed * s),
          timestamp: end.subtract(Duration(seconds: s)),
          speedMps: speed,
          headingDeg: Geo.bearingDeg(
              ConvoyPredictor.pointAlong(road, endAlong - speed * s - 50), ConvoyPredictor.pointAlong(road, endAlong - speed * s + 50)),
          accuracyM: accuracy,
        ),
    ];

// ───────────────────────────── fakes ─────────────────────────────

SupabaseClient fakeDb() => SupabaseClient('https://preview.supabase.co', 'anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false));

class NoSignaller implements PttSignaller {
  @override
  Stream<Map<String, dynamic>> get ptt => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get signals => const Stream.empty();
  @override
  Future<bool> sendPtt(Map<String, dynamic> body) async => true;
  @override
  Future<bool> sendSignal(String to, Map<String, dynamic> body) async => true;
}

/// A trip session driven by sample data instead of Supabase.
class PreviewSession extends TripSession {
  PreviewSession(this.tracks, {this.predictAll = false}) : super(fakeDb(), tripId) {
    this.trip = trip_;
    this.members = {...membersMap};
    me = membersMap[mAngith];
    this.itinerary = itinerary_;
    loading = false;
    online = {mAngith, mRavi, mPriya};
    ptt = PttService(selfId: mAngith, signaller: NoSignaller());
    messages.addAll(sampleMessages());
  }

  static final trip_ = trip;
  static final membersMap = members;
  static final itinerary_ = itinerary;

  final Map<String, List<VehiclePosition>> tracks;
  final bool predictAll;
  bool lockTyping = false;

  @override
  bool get drivingLock => lockTyping;

  Map<String, VehiclePosition> get _latest => {for (final e in tracks.entries) e.key: e.value.last};

  @override
  String? get userId => uAngith;

  @override
  List<GeoPoint> get routeLine => road;

  @override
  VehiclePosition? lastReported(String memberId) => tracks[memberId]?.last;

  @override
  Map<String, VehiclePosition> get positions {
    final labels = {for (final m in members.values) m.id: m.vehicleLabel ?? m.displayName};
    return {
      for (final e in _latest.entries)
        e.key: (e.key != mAngith && now.difference(e.value.timestamp) > const Duration(seconds: 30))
            ? const ConvoyPredictor().predict(
                last: e.value,
                route: road,
                history: tracks,
                latest: _latest,
                stops: itinerary.waypoints,
                now: now,
                labels: labels,
                averageSpeed: 21,
                roadSpeedAt: (_) => 24,
              )
            : e.value,
    };
  }

  @override
  LeadResult? get lead {
    final r = const LeadVehicleResolver().resolve(designatedMemberId: mRavi, positions: _latest, route: road, now: now);
    if (r == null || r.reason != LeadReason.designatedSilent) return r;
    return LeadResult(r.memberId, r.reason, Geo.projectOntoRoute(road, positions[r.memberId]!.point).alongMeters);
  }

  @override
  List<ConvoyStanding> get standings =>
      const LeadVehicleResolver().standings(lead: lead, positions: _latest, route: road, now: now);

}

List<ChatMessage> sampleMessages() {
  ChatMessage m(String id, String sender, String name, String body, int minsAgo, {String kind = 'text', bool mesh = false, bool pending = false}) =>
      ChatMessage(
          id: id, tripId: tripId, senderId: sender, senderName: name, body: body, kind: kind,
          createdAt: now.subtract(Duration(minutes: minsAgo)), viaMesh: mesh, pending: pending);
  return [
    m('c1', 'u3', 'Priya', 'joined the convoy', 95, kind: 'system'),
    m('c2', 'u2', 'Ravi', 'Leaving Bidadi now, 5 min behind plan', 62),
    m('c3', uAngith, 'Angith', 'Running 10 min late. Schedule updated.', 61, kind: 'quick'),
    m('c4', 'u3', 'Priya', 'Fuel soon', 34, kind: 'quick'),
    m('c5', uAngith, 'Angith', 'HP at Maddur is on the left, everyone fill up there', 33),
    m('c6', 'u2', 'Ravi', 'Ok, indicator on 500 m before', 32),
    m('c7', 'u4', 'Arjun', 'Network gone after Mandya, following you on the radio', 9, mesh: true),
    m('c8', uAngith, 'Angith', 'All good', 1, kind: 'quick', pending: true),
  ];
}

class FakeTripRepo extends TripRepository {
  FakeTripRepo() : super(fakeDb());

  @override
  Future<List<JoinRequest>> joinRequests(String tripId) async => [
        JoinRequest(
          id: 'jr1',
          tripId: tripId,
          requesterId: 'u9',
          requesterName: 'Nikhil',
          status: JoinRequestStatus.pending,
          vehicleLabel: 'Black Fortuner',
          message: 'Driving down the same weekend, happy to sweep at the back.',
          requesterAcceptedTerms: true,
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
      ];
}

class FakeGuidelines extends GuidelineRepository {
  FakeGuidelines() : super(fakeDb());

  @override
  Future<List<GuidelineDocument>> current() async {
    final seed = File('../supabase/seed.sql').readAsStringSync();
    String body(String title) {
      final start = seed.indexOf(r'$$', seed.indexOf(title)) + 2;
      return seed.substring(start, seed.indexOf(r'$$', start)).trim();
    }

    return [
      GuidelineDocument(id: 'd2', kind: 'driver_terms', version: 1, title: 'Driver terms', body: body("'Driver terms'")),
      GuidelineDocument(id: 'd1', kind: 'platform_guidelines', version: 1, title: 'DriveSync community guidelines', body: body("'DriveSync community guidelines'")),
    ];
  }
}

class FakeEdge extends EdgeRepository {
  FakeEdge() : super(EdgeClient(fakeDb(), baseUrl: 'https://edge.preview'));

  @override
  Future<List<AffiliateOffer>> offersAlongRoute(List<GeoPoint> route, {Set<OfferCategory>? categories, String? tripId}) async => [
        AffiliateOffer(id: 's1', category: OfferCategory.hotel, name: 'Heritage stay, Srirangapatna', location: road[300], provider: 'Karnataka Tourism', detourKm: 1.8, alongKm: 128, sponsored: true, bookingUrl: 'https://x', priceHint: 'from ₹3,400'),
        AffiliateOffer(id: 'o1', category: OfferCategory.fuel, name: 'Indian Oil, Mandya bypass', location: road[240], provider: 'openstreetmap', detourKm: 0.2, alongKm: 102),
        AffiliateOffer(id: 'o2', category: OfferCategory.restArea, name: 'Highway rest area, Srirangapatna', location: road[290], provider: 'openstreetmap', detourKm: 0.1, alongKm: 121),
        AffiliateOffer(id: 'o3', category: OfferCategory.hotel, name: 'Royal Orchid Metropole, Mysuru', location: road[320], provider: 'openstreetmap', detourKm: 1.2, alongKm: 140, bookingUrl: 'https://x', rating: 4.4),
        AffiliateOffer(id: 'o4', category: OfferCategory.campsite, name: 'Dubare riverside camp', location: road[440], provider: 'openstreetmap', detourKm: 6.5, alongKm: 221, bookingUrl: 'https://x'),
        AffiliateOffer(id: 'o5', category: OfferCategory.fuel, name: 'Bharat Petroleum, Hunsur', location: road[370], provider: 'openstreetmap', detourKm: 0.4, alongKm: 176),
        AffiliateOffer(id: 'o6', category: OfferCategory.campsite, name: 'Harangi backwater tents', location: road[460], provider: 'openstreetmap', detourKm: 9.1, alongKm: 232, bookingUrl: 'https://x'),
      ];

  @override
  Future<DiscoveryResult> discover(GeoPoint near, {double radiusKm = 300, List<String> tags = const []}) async => DiscoveryResult([
        PublicTrip(id: 't1', title: 'Chikmagalur coffee trail', summary: 'Easy pace, two days, homestay booked. Families welcome.', ownerName: 'Meera', ownerVerified: true, start: const GeoPoint(12.97, 77.59), end: const GeoPoint(13.32, 75.77), vehicleCount: 3, openSlots: 4, startsAt: now.add(const Duration(days: 9)), tags: const ['family', 'coffee'], distanceKm: 4),
        PublicTrip(id: 't2', title: 'Spiti in 10 days (4x4 only)', summary: 'High passes, river crossings. Recovery gear mandatory.', ownerName: 'Off-road Bengaluru', ownerVerified: true, start: const GeoPoint(12.95, 77.6), end: const GeoPoint(32.2, 78.0), vehicleCount: 6, openSlots: 2, startsAt: now.add(const Duration(days: 30)), tags: const ['4x4', 'mountains'], distanceKm: 7),
        PublicTrip(id: 't3', title: 'Nandi Hills sunrise ride', summary: 'Bikes and cars, back by 10 am.', ownerName: 'Karthik', ownerVerified: false, start: const GeoPoint(13.03, 77.6), end: const GeoPoint(13.37, 77.68), vehicleCount: 9, openSlots: 0, startsAt: now.add(const Duration(days: 2)), tags: const ['bikes'], distanceKm: 9),
      ], const [
        SponsoredPlacement(name: 'Coorg monsoon trails: official guide', partner: 'Karnataka Tourism', category: 'attraction', url: 'https://x', distanceKm: 210),
        SponsoredPlacement(name: 'Kamat Lokaruchi highway dining', partner: 'Kamat Hotels', category: 'rest_area', url: 'https://x', distanceKm: 38),
      ]);
}

class FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => Position(
      latitude: 12.97, longitude: 77.59, timestamp: now, accuracy: 10, altitude: 900, altitudeAccuracy: 5,
      heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
}

class FakeIap extends InAppPurchasePlatform {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async => ProductDetailsResponse(
        productDetails: [
          ProductDetails(id: 'convoy_premium_monthly', title: 'Premium monthly (Convoy)', description: '', price: '₹149', rawPrice: 149, currencyCode: 'INR'),
          ProductDetails(id: 'convoy_premium_yearly', title: 'Premium yearly (Convoy)', description: '', price: '₹1,199', rawPrice: 1199, currencyCode: 'INR'),
        ],
        notFoundIDs: const [],
      );
}

// ───────────────────────────── map backdrop ─────────────────────────────

/// Paints a quiet road-map backdrop plus the convoy exactly as ConvoyMap
/// styles it (route, stops, halos, lead ring, labels).
class MapPreview extends CustomPainter {
  MapPreview(this.s, {required this.focus, this.topPad = 150, this.bottomPad = 230, this.dark = false});

  final TripSession s;
  final bool dark;
  Tones get _wf => dark ? Tones.dark : Tones.light;
  final List<GeoPoint> focus;
  final double topPad, bottomPad;

  @override
  void paint(Canvas canvas, Size size) {
    final b = GeoBounds.around(focus, padMeters: 600);
    const sidePad = 70.0;
    double mx(double lng) => (lng + 180) / 360;
    double my(double lat) {
      final r = lat * math.pi / 180;
      return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
    }

    final x0 = mx(b.west), x1 = mx(b.east), y0 = my(b.north), y1 = my(b.south);
    final availH = size.height - topPad - bottomPad;
    final scale = math.min((size.width - 2 * sidePad) / (x1 - x0), availH / (y1 - y0));
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    Offset p(GeoPoint g) => Offset(size.width / 2 + (mx(g.lng) - cx) * scale, topPad + availH / 2 + (my(g.lat) - cy) * scale);
    final metersPerPx = 40075016.0 * math.cos(focus.first.lat * math.pi / 180) / scale;

    // Land, parks, water, minor roads.
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF151B27) : const Color(0xFFF2EFE9));
    final rnd = math.Random(7);
    final park = Paint()..color = dark ? const Color(0xFF18291F) : const Color(0xFFD8EBCF);
    for (var i = 0; i < 9; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), width: 60 + rnd.nextDouble() * 120, height: 40 + rnd.nextDouble() * 90),
              const Radius.circular(30)),
          park);
    }
    final river = Path()..moveTo(-20, size.height * 0.30);
    river.cubicTo(size.width * 0.3, size.height * 0.22, size.width * 0.55, size.height * 0.55, size.width + 20, size.height * 0.48);
    canvas.drawPath(river, Paint()..color = dark ? const Color(0xFF1C3550) : const Color(0xFFAAD3DF)..style = PaintingStyle.stroke..strokeWidth = 14);
    final minor = Paint()..color = dark ? const Color(0xFF2A3445) : Colors.white..style = PaintingStyle.stroke..strokeWidth = 4;
    final minorEdge = Paint()..color = dark ? const Color(0xFF1E2634) : const Color(0xFFDAD5CC)..style = PaintingStyle.stroke..strokeWidth = 6;
    for (var i = 0; i < 14; i++) {
      final a = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final c = a + Offset(rnd.nextDouble() * 300 - 150, rnd.nextDouble() * 300 - 150);
      final path = Path()..moveTo(a.dx, a.dy)..quadraticBezierTo((a.dx + c.dx) / 2 + 30, (a.dy + c.dy) / 2 - 20, c.dx, c.dy);
      canvas.drawPath(path, minorEdge);
      canvas.drawPath(path, minor);
    }

    // Route: highway casing + Convoy's blue line.
    final route = Path();
    for (var i = 0; i < road.length; i++) {
      final o = p(road[i]);
      i == 0 ? route.moveTo(o.dx, o.dy) : route.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(route, Paint()..color = dark ? const Color(0xFF6B4A22) : const Color(0xFFF9B26B)..style = PaintingStyle.stroke..strokeWidth = 11..strokeJoin = StrokeJoin.round);
    canvas.drawPath(route, Paint()..color = _wf.accent..style = PaintingStyle.stroke..strokeWidth = 5..strokeJoin = StrokeJoin.round..strokeCap = StrokeCap.round);

    for (final w in s.itinerary.waypoints) {
      final o = p(w.location);
      if (o.dx < -50 || o.dx > size.width + 50 || o.dy < -50 || o.dy > size.height + 50) continue;
      canvas.drawCircle(o, 7, Paint()..color = _wf.card);
      canvas.drawCircle(o, 7, Paint()..color = _wf.accent..style = PaintingStyle.stroke..strokeWidth = 3);
      _text(canvas, w.name, o + const Offset(0, 12), 12, top: true);
    }

    final lead = s.lead?.memberId;
    final pos = s.positions;
    final placed = <Rect>[];
    for (final v in pos.values) {
      final o = p(v.point);
      final color = Color(s.members[v.memberId]?.vehicleColor ?? 0xFF2E7DF6);
      final stale = now.difference(s.lastReported(v.memberId)?.timestamp ?? now) > const Duration(seconds: 90);
      final halo = math.max(v.source == PositionSource.estimated ? 14.0 : 8.0, v.accuracyM / metersPerPx);
      canvas.drawCircle(o, halo, Paint()..color = color.withValues(alpha: v.source == PositionSource.estimated ? 0.18 : 0.1));
      if (v.source == PositionSource.estimated) {
        canvas.drawCircle(o, halo, Paint()..color = color.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
      if (v.memberId == lead) {
        canvas.drawCircle(o, 16, Paint()..color = _wf.warn..style = PaintingStyle.stroke..strokeWidth = 4);
      }
      canvas.drawCircle(o, 10, Paint()..color = color.withValues(alpha: stale && v.source != PositionSource.estimated ? 0.45 : 1));
      canvas.drawCircle(o, 10, Paint()..color = _wf.card..style = PaintingStyle.stroke..strokeWidth = 3);
      final m = s.members[v.memberId];
      final name = v.memberId == s.me?.id ? 'You' : (m?.vehicleLabel ?? m?.displayName ?? 'Vehicle');
      final via = switch (v.source) {
        PositionSource.mesh => ' (off-grid)',
        PositionSource.estimated => ' (est.)',
        _ => '',
      };
      // Like MapLibre's variable anchors: above, below, left or right of
      // the dot, whichever is free.
      final label = '$name${v.memberId == lead ? ', lead' : ''}$via';
      final w = _measure(label, 13).width + 8, h = 20.0;
      final candidates = [
        Rect.fromCenter(center: o - const Offset(0, 28), width: w, height: h),
        Rect.fromCenter(center: o + const Offset(0, 28), width: w, height: h),
        Rect.fromLTWH(o.dx - 22 - w, o.dy - h / 2, w, h),
        Rect.fromLTWH(o.dx + 22, o.dy - h / 2, w, h),
      ];
      final spot = candidates.firstWhere((r) => !placed.any((q) => q.overlaps(r)), orElse: () => candidates.first);
      placed.add(spot);
      _text(canvas, label, Offset(spot.center.dx, spot.top + 2), 13, bold: true, top: true);
    }
  }

  Size _measure(String t, double size) =>
      (TextPainter(text: TextSpan(text: t, style: TextStyle(fontFamily: 'Roboto', fontSize: size, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout()).size;

  void _text(Canvas c, String t, Offset at, double size, {bool top = false, bool bold = false}) {
    final style = TextStyle(
        fontFamily: 'Roboto', fontSize: size, color: _wf.ink, fontWeight: bold ? FontWeight.w600 : FontWeight.w500);
    final halo = TextPainter(
      text: TextSpan(
          text: t,
          style: style.copyWith(
              foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = _wf.card)),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp = TextPainter(text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr)..layout();
    final o = Offset(at.dx - tp.width / 2, top ? at.dy : at.dy - tp.height);
    halo.paint(c, o);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ───────────────────────────── harness ─────────────────────────────

Future<void> loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

ThemeData theme({bool dark = false}) =>
    dark ? ConvoyTheme.dark(fontFamily: 'Roboto') : ConvoyTheme.light(fontFamily: 'Roboto');

/// Android-style status bar painted over the top inset.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, this.signal = true, this.dark = false});
  final bool signal;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = dark ? Colors.white : Colors.black87;
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Text('10:42', style: TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w600, color: c)),
            const Spacer(),
            Icon(Icons.location_on, size: 14, color: c),
            const SizedBox(width: 6),
            Icon(signal ? Icons.signal_cellular_alt : Icons.signal_cellular_off, size: 15, color: c),
            const SizedBox(width: 4),
            if (signal) Icon(Icons.wifi, size: 15, color: c),
            const SizedBox(width: 4),
            Icon(Icons.battery_5_bar, size: 15, color: c),
          ]),
        ),
        ),
      ),
    );
  }
}

/// The trip shell (as TripScreen builds it) around one tab.
Widget tripShell(TripSession s, int tab, Widget body, {Widget? backdrop}) => Stack(children: [
      if (backdrop != null) Positioned.fill(child: backdrop),
      Scaffold(
        backgroundColor: backdrop != null ? Colors.transparent : null,
        extendBody: true,
        body: body,
        bottomNavigationBar: FloatingNavBar(
          index: tab,
          onTap: (_) {},
          items: [
            const FloatingNavItem(Icons.map_outlined, Icons.map_rounded, 'Map'),
            const FloatingNavItem(Icons.route_outlined, Icons.route_rounded, 'Plan'),
            FloatingNavItem(Icons.forum_outlined, Icons.forum_rounded, 'Chat', badge: tab == 2 ? 0 : 3),
            const FloatingNavItem(Icons.groups_outlined, Icons.groups_rounded, 'Convoy'),
            const FloatingNavItem(Icons.storefront_outlined, Icons.storefront_rounded, 'Stops'),
          ],
        ),
      ),
    ]);

Future<void> shoot(WidgetTester tester, String name, Widget screen,
    {bool signal = true, bool premium = false, bool dark = false, Duration settle = const Duration(milliseconds: 600)}) async {
  final key = GlobalKey();
  // flutter_test swaps shadows for black outlines by default; render real ones.
  debugDisableShadows = false;
  tester.view.physicalSize = _logical * _dpr;
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = const FakeViewPadding(top: 28 * _dpr, bottom: 16 * _dpr);
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(fakeDb()),
        tripRepositoryProvider.overrideWithValue(FakeTripRepo()),
        guidelineRepositoryProvider.overrideWithValue(FakeGuidelines()),
        edgeRepositoryProvider.overrideWithValue(FakeEdge()),
        entitlementProvider.overrideWith((ref) async => Entitlement(tier: premium ? Tier.premium : Tier.free)),
        verifiedPartyProvider.overrideWith((ref) async => true),
        acceptedGuidelinesProvider.overrideWith((ref) async => true),
        myTripsProvider.overrideWith((ref) async => [
              trip,
              Trip(id: 't2', ownerId: 'x', title: 'Gokarna beach run', inviteCode: 'B3HV8WQE', visibility: TripVisibility.private, startsAt: now.add(const Duration(days: 21))),
              Trip(id: 't3', ownerId: 'x', title: 'Diwali family drive to Ooty', inviteCode: 'P2LM4KAD', visibility: TripVisibility.private, startsAt: now.subtract(const Duration(days: 40))),
            ]),
        currentUserProvider.overrideWithValue(User(
            id: uAngith, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated',
            createdAt: now.toIso8601String(), email: 'angith@example.com')),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme(),
        darkTheme: theme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Stack(children: [screen, Positioned(top: 0, left: 0, right: 0, child: StatusBar(signal: signal, dark: dark))]),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(settle ~/ 6);
  }
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_out/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'meshtastic.device': 'F4:12:FA:9C:31:0E'});
    GeolocatorPlatform.instance = FakeGeolocator();
    // InAppPurchase registers the real Play Billing implementation on first
    // use when the target is Android; create it under a neutral platform so
    // the fake store below is the one used.
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
    InAppPurchasePlatform.instance = FakeIap();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // MapLibre's global channel: two cached offline packs.
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/maplibre_gl'), (call) async {
      if (call.method == 'getListOfRegions') {
        Map<String, dynamic> pack(int id, String name, List<double> b, double z) => {
              'id': id,
              'definition': {
                'bounds': [[b[0], b[1]], [b[2], b[3]]],
                'mapStyleUrl': 'https://tiles.openfreemap.org/styles/liberty',
                'minZoom': 5.0,
                'maxZoom': z,
              },
              'metadata': {'name': name, 'tripId': tripId},
            };
        return jsonEncode([
          pack(1, 'Coorg weekend (1/4)', [12.80, 77.20, 13.05, 77.70], 12),
          pack(2, 'Coorg weekend (2/4)', [12.45, 76.75, 12.85, 77.25], 12),
          pack(3, 'Coorg weekend (3/4)', [12.20, 76.20, 12.55, 76.80], 12),
          pack(4, 'Coorg weekend (4/4)', [12.30, 75.65, 12.55, 76.25], 12),
        ]);
      }
      return null;
    });
    for (var i = 0; i < 32; i++) {
      messenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/maplibre_gl_$i'), (call) async => null);
    }
    // Platform views (the MapLibre surface) render nothing in tests.
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async => call.method == 'create' ? 0 : null);
  });

  final liveTracks = {
    mRavi: track(mRavi, leadAlong, now.subtract(const Duration(seconds: 3))),
    mPriya: track(mPriya, leadAlong - 1200, now.subtract(const Duration(seconds: 5))),
    mAngith: track(mAngith, leadAlong - 3100, now.subtract(const Duration(seconds: 1))),
    mArjun: track(mArjun, leadAlong - 3500, now.subtract(const Duration(minutes: 9)), speed: 21),
  };

  List<GeoPoint> convoyFocus(TripSession s) => [for (final p in s.positions.values) p.point];

  testWidgets('01 sign in', (t) => shoot(t, '01_sign_in', const SignInScreen()));
  testWidgets('02 guidelines', (t) => shoot(t, '02_guidelines', const GuidelinesScreen()));
  testWidgets('03 home', (t) => shoot(t, '03_home', const HomeScreen()));

  testWidgets('04 map live', (t) async {
    final s = PreviewSession(liveTracks);
    s.ptt!.talking.value = mRavi;
    await shoot(t, '04_map_live', tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s)))), premium: true);
  });

  testWidgets('05 map no signal (predicted)', (t) async {
    final offline = {
      mRavi: track(mRavi, leadAlong - 9000, now.subtract(const Duration(minutes: 7))),
      mPriya: track(mPriya, leadAlong - 10200, now.subtract(const Duration(minutes: 7))),
      mAngith: track(mAngith, leadAlong - 4000, now.subtract(const Duration(seconds: 1))),
      mArjun: track(mArjun, leadAlong - 12500, now.subtract(const Duration(minutes: 7)), speed: 0),
    };
    final s = PreviewSession(offline)..link = LinkMode.isolated;
    s.online = {mAngith};
    await shoot(t, '05_map_offline_predicted', tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s)))), signal: false, premium: true);
  });

  testWidgets('06 map on convoy radio', (t) async {
    VehiclePosition viaRadio(VehiclePosition p) => VehiclePosition(
        memberId: p.memberId, point: p.point, timestamp: p.timestamp, speedMps: p.speedMps, headingDeg: p.headingDeg, accuracyM: p.accuracyM, source: PositionSource.mesh);
    final radio = {
      for (final e in liveTracks.entries)
        e.key: e.key == mAngith || e.key == mArjun ? e.value : [...e.value.sublist(0, e.value.length - 1), viaRadio(e.value.last)],
    };
    final s = PreviewSession(radio)
      ..link = LinkMode.radio
      ..meshPeersOn = ((t) => t == 'lora' ? 3 : 0);
    s.online = {mAngith};
    await shoot(t, '06_map_radio', tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s)))), signal: false, premium: true);
  });

  testWidgets('07 plan', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, '07_plan', tripShell(s, 1, ItineraryTab(session: s)), premium: true);
  });

  testWidgets('08 chat', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, '08_chat', tripShell(s, 2, ChatTab(session: s)), premium: true);
  });

  testWidgets('09 convoy', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, '09_convoy', tripShell(s, 3, ConvoyTab(session: s)), premium: true);
  });

  testWidgets('10 stops', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, '10_stops', tripShell(s, 4, StopsTab(session: s)), premium: true);
  });

  // Dark mode.
  testWidgets('d01 sign in dark', (t) => shoot(t, 'd01_sign_in_dark', const SignInScreen(), dark: true));
  testWidgets('d03 home dark', (t) => shoot(t, 'd03_home_dark', const HomeScreen(), dark: true));
  testWidgets('d04 map dark', (t) async {
    final s = PreviewSession(liveTracks);
    s.ptt!.talking.value = mRavi;
    await shoot(t, 'd04_map_live_dark',
        tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s), dark: true))),
        premium: true, dark: true);
  });
  testWidgets('d08 chat dark', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, 'd08_chat_dark', tripShell(s, 2, ChatTab(session: s)), premium: true, dark: true);
  });
  testWidgets('d09 convoy dark', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, 'd09_convoy_dark', tripShell(s, 3, ConvoyTab(session: s)), premium: true, dark: true);
  });
  testWidgets('d07 plan dark', (t) async {
    final s = PreviewSession(liveTracks);
    await shoot(t, 'd07_plan_dark', tripShell(s, 1, ItineraryTab(session: s)), premium: true, dark: true);
  });

  // Convoy Watch.
  List<ConvoyAlert> sampleAlerts() => [
        ConvoyAlert(kind: AlertKind.fallingBehind, memberId: mArjun, message: 'Ertiga is 3.4 km behind Swift', at: now),
        ConvoyAlert(kind: AlertKind.planChanged, memberId: null, message: 'Plan updated. Ravi: Lunch: Mysuru now at 12:10', at: now),
      ];
  testWidgets('15 map alerts', (t) async {
    final s = PreviewSession(liveTracks);
    s.alerts.addAll(sampleAlerts());
    await shoot(t, '15_map_alerts', tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s)))),
        premium: true);
  });
  testWidgets('16 chat driving lock', (t) async {
    final s = PreviewSession(liveTracks)..lockTyping = true;
    await shoot(t, '16_chat_driving', tripShell(s, 2, ChatTab(session: s)), premium: true);
  });
  testWidgets('d15 map alerts dark', (t) async {
    final s = PreviewSession(liveTracks);
    s.alerts.addAll([
      ConvoyAlert(kind: AlertKind.unplannedStop, memberId: mArjun, message: 'Ertiga has stopped for 4 min. Not a planned stop.', at: now),
    ]);
    await shoot(t, 'd15_map_alerts_dark',
        tripShell(s, 0, MapTab(session: s), backdrop: CustomPaint(painter: MapPreview(s, focus: convoyFocus(s), dark: true))),
        premium: true, dark: true);
  });
  testWidgets('d16 chat driving lock dark', (t) async {
    final s = PreviewSession(liveTracks)..lockTyping = true;
    await shoot(t, 'd16_chat_driving_dark', tripShell(s, 2, ChatTab(session: s)), premium: true, dark: true);
  });

  testWidgets('11 discover', (t) => shoot(t, '11_discover', const DiscoverScreen()));
  testWidgets('12 premium', (t) => shoot(t, '12_premium', const PaywallScreen()));
  testWidgets('13 radio pairing', (t) => shoot(t, '13_radio', const RadioScreen()));
  testWidgets('14 offline maps', (t) => shoot(t, '14_offline_maps', const OfflineMapsScreen()));
}
