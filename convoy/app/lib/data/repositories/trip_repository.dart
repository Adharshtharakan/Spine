import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/geo/geo.dart';
import '../models/social.dart';
import '../models/trip.dart';

/// Turns Postgres exceptions raised by the RPCs into messages a driver can
/// act on. The SQL raises stable codes (`vehicle_cap_reached`, …) with a hint.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    const known = {
      'guidelines_not_accepted': 'Please accept the current guidelines and driver terms first.',
      'vehicle_cap_reached': 'This convoy is full on the free plan (2 vehicles). The organiser can upgrade for larger convoys.',
      'invalid_invite': 'That invite code was not found.',
      'not_verified': 'Confirm your phone number and accept the current terms to do this.',
      'trip_not_open': 'This trip is no longer open to join.',
      'already_member': 'You are already in this convoy.',
      'requester_terms_outdated': 'The traveller needs to accept the updated guidelines first.',
      'not_allowed': 'Only the organiser or the lead vehicle can do that.',
      'not_owner': 'Only the organiser can do that.',
      'driver_attestation_required': 'Please confirm all three driver statements.',
    };
    for (final entry in known.entries) {
      if (e.message.contains(entry.key)) return e.hint ?? entry.value;
    }
    return e.message;
  }
  if (e is AuthException) return e.message;
  return e.toString();
}

class TripRepository {
  TripRepository(this._db);

  final SupabaseClient _db;

  String? get userId => _db.auth.currentUser?.id;

  Future<List<Trip>> myTrips() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _db
        .from('trip_members')
        .select('trips(*)')
        .eq('user_id', uid)
        .order('joined_at', ascending: false);
    return [
      for (final r in rows)
        if (r['trips'] != null) Trip.fromRow(r['trips'] as Map<String, dynamic>),
    ];
  }

  Future<Trip> trip(String id) async =>
      Trip.fromRow(await _db.from('trips').select().eq('id', id).single());

  Stream<Trip> watchTrip(String id) => _db
      .from('trips')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => Trip.fromRow(rows.first));

  Future<List<TripMember>> members(String tripId) async {
    final rows = await _db
        .from('trip_members')
        .select('*, profiles:user_id(display_name)')
        .eq('trip_id', tripId);
    return rows.map(TripMember.fromRow).toList();
  }

  Future<Trip> create(String title, {String description = '', DateTime? startsAt, String? vehicleLabel}) async {
    final row = await _db.rpc('create_trip', params: {
      'p_title': title,
      'p_description': description,
      'p_starts_at': startsAt?.toUtc().toIso8601String(),
      'p_vehicle_label': vehicleLabel,
    });
    return Trip.fromRow(row as Map<String, dynamic>);
  }

  Future<Trip> joinByInvite(String code, {String? vehicleLabel, bool hasVehicle = true}) async {
    final row = await _db.rpc('join_by_invite', params: {
      'p_code': code,
      'p_vehicle_label': vehicleLabel,
      'p_has_vehicle': hasVehicle,
    });
    return Trip.fromRow(row as Map<String, dynamic>);
  }

  Future<void> setLead(String tripId, String memberId) =>
      _db.rpc('set_lead_vehicle', params: {'p_trip': tripId, 'p_member': memberId});

  Future<void> updateMyVehicle(String memberId, {String? label, int? color, bool? hasVehicle}) =>
      _db.from('trip_members').update({
        'vehicle_label': ?label,
        if (color != null) 'vehicle_color': color.toSigned(32),
        'has_vehicle': ?hasVehicle,
      }).eq('id', memberId);

  Future<void> leave(String memberId) => _db.from('trip_members').delete().eq('id', memberId);

  /// Last-known positions for members who are not currently broadcasting.
  Future<List<VehiclePosition>> lastKnownPositions(String tripId) async {
    final rows = await _db.from('member_locations').select().eq('trip_id', tripId);
    return [
      for (final r in rows)
        VehiclePosition(
          memberId: r['member_id'] as String,
          point: GeoPoint((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
          timestamp: DateTime.parse(r['recorded_at'] as String).toUtc(),
          speedMps: (r['speed_mps'] as num).toDouble(),
          headingDeg: (r['heading_deg'] as num).toDouble(),
          accuracyM: (r['accuracy_m'] as num).toDouble(),
        ),
    ];
  }

  Future<void> saveLastKnown(String tripId, VehiclePosition p) async {
    final uid = userId;
    if (uid == null) return;
    await _db.from('member_locations').upsert({
      'member_id': p.memberId,
      'trip_id': tripId,
      'user_id': uid,
      'lat': p.point.lat,
      'lng': p.point.lng,
      'speed_mps': p.speedMps,
      'heading_deg': p.headingDeg,
      'accuracy_m': p.accuracyM,
      'recorded_at': p.timestamp.toUtc().toIso8601String(),
    });
  }

  // ───────────── discovery: publishing & mutual acceptance ─────────────

  Future<Trip> publish(String tripId,
      {required String summary,
      required List<String> tags,
      required GeoPoint start,
      required GeoPoint end,
      int? maxVehicles}) async {
    final row = await _db.rpc('publish_trip', params: {
      'p_trip': tripId,
      'p_summary': summary,
      'p_tags': tags,
      'p_start_lat': start.lat,
      'p_start_lng': start.lng,
      'p_end_lat': end.lat,
      'p_end_lng': end.lng,
      'p_max_vehicles': maxVehicles,
    });
    return Trip.fromRow(row as Map<String, dynamic>);
  }

  Future<void> unpublish(String tripId) => _db.rpc('unpublish_trip', params: {'p_trip': tripId});

  Future<void> requestToJoin(String tripId, {required String vehicleLabel, String message = ''}) =>
      _db.rpc('request_to_join', params: {
        'p_trip': tripId,
        'p_vehicle_label': vehicleLabel,
        'p_message': message,
      });

  Future<List<JoinRequest>> joinRequests(String tripId) async {
    final rows = await _db
        .from('join_requests')
        .select('*, profiles:requester_id(display_name)')
        .eq('trip_id', tripId)
        .order('created_at');
    return rows.map(JoinRequest.fromRow).toList();
  }

  Future<List<JoinRequest>> myJoinRequests() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _db
        .from('join_requests')
        .select('*, profiles:requester_id(display_name)')
        .eq('requester_id', uid)
        .order('created_at', ascending: false);
    return rows.map(JoinRequest.fromRow).toList();
  }

  Future<void> decide(String requestId, {required bool approve}) =>
      _db.rpc('decide_join_request', params: {'p_request': requestId, 'p_approve': approve});

  Future<void> withdraw(String requestId) =>
      _db.from('join_requests').update({'status': 'withdrawn'}).eq('id', requestId);
}

class GuidelineRepository {
  GuidelineRepository(this._db);

  final SupabaseClient _db;

  /// The latest published version of each document kind.
  Future<List<GuidelineDocument>> current() async {
    final rows = await _db
        .from('guideline_documents')
        .select()
        .order('version', ascending: false);
    final byKind = <String, GuidelineDocument>{};
    for (final r in rows) {
      final d = GuidelineDocument.fromRow(r);
      byKind.putIfAbsent(d.kind, () => d);
    }
    return byKind.values.toList()..sort((a, b) => a.kind.compareTo(b.kind));
  }

  Future<bool> hasAcceptedCurrent() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await _db.rpc('has_accepted_current', params: {'uid': uid});
    return res == true;
  }

  Future<bool> isVerifiedParty() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;
    return await _db.rpc('is_verified_party', params: {'uid': uid}) == true;
  }

  Future<void> accept(GuidelineDocument doc, {Map<String, bool> attestation = const {}}) =>
      _db.rpc('accept_guideline', params: {'document': doc.id, 'attestation': attestation});
}

class EntitlementRepository {
  EntitlementRepository(this._db);

  final SupabaseClient _db;

  Future<Entitlement> mine() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return Entitlement.free;
    final row = await _db.from('entitlements').select().eq('user_id', uid).maybeSingle();
    if (row == null) return Entitlement.free;
    return Entitlement(
      tier: row['tier'] == 'premium' ? Tier.premium : Tier.free,
      expiresAt: row['expires_at'] == null ? null : DateTime.parse(row['expires_at'] as String),
    );
  }
}
