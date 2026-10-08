import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/geo/geo.dart';
import '../data/models/social.dart';
import '../data/models/trip.dart';
import '../data/models/waypoint.dart';
import '../data/repositories/trip_repository.dart';
import '../services/location/gps_service.dart';
import '../services/offline/outbox.dart';
import '../services/realtime/convoy_channel.dart';
import '../services/tracking/dead_reckoning.dart';
import '../services/tracking/lead_vehicle.dart';
import '../services/voice/ptt_service.dart';
import '../sync/itinerary_doc.dart';

/// How the convoy is currently being kept in sync.
enum LinkMode {
  /// Supabase Realtime is live.
  cloud,

  /// No internet, but peers are reachable over the BLE/Wi-Fi mesh.
  mesh,

  /// Neither: own GPS still plots; others are dead-reckoned.
  isolated,
}

/// Everything for one open trip: itinerary replication, live positions,
/// lead identification, chat and push-to-talk. Screens listen to it.
class TripSession extends ChangeNotifier {
  TripSession(this._db, this.tripId) : _repo = TripRepository(_db);

  final SupabaseClient _db;
  final TripRepository _repo;
  final String tripId;
  static const _uuid = Uuid();

  Trip? trip;
  Map<String, TripMember> members = {};
  TripMember? me;
  late ItineraryDoc itinerary;
  final Map<String, VehiclePosition> _reported = {};
  final List<ChatMessage> messages = [];
  Set<String> online = {};
  LinkMode link = LinkMode.cloud;
  bool loading = true;
  String? error;
  int pendingWrites = 0;

  ConvoyChannel? channel;
  GpsService? gps;
  PttService? ptt;
  Outbox? _outbox;
  GpsPermission? gpsPermission;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _ticker;
  DateTime _lastBroadcast = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hooks for the offline mesh (step 5): set by [attachMesh].
  Future<void> Function(VehiclePosition p)? meshSendPosition;
  Future<void> Function(ChatMessage m)? meshSendChat;
  Future<void> Function(Waypoint w)? meshSendWaypoint;
  bool Function()? meshHasPeers;

  static const _resolver = LeadVehicleResolver();
  static const _reckoner = DeadReckoning();

  String? get userId => _db.auth.currentUser?.id;
  bool get isOwner => trip?.ownerId == userId;

  /// Positions to draw: fresh reports as-is; silent vehicles projected
  /// forward along the route so the map never just freezes in a dead zone.
  Map<String, VehiclePosition> get positions {
    final now = DateTime.now();
    final route = itinerary.route;
    return {
      for (final e in _reported.entries)
        e.key: (e.key != me?.id && e.value.age(now) > const Duration(seconds: 30))
            ? _reckoner.estimate(e.value, route, now)
            : e.value,
    };
  }

  LeadResult? get lead => _resolver.resolve(
        designatedMemberId: trip?.leadMemberId,
        positions: _reported,
        route: itinerary.route,
      );

  List<ConvoyStanding> get standings =>
      _resolver.standings(lead: lead, positions: _reported, route: itinerary.route);

  Waypoint? get nextStop => itinerary.nextStop(lead?.alongMeters ?? 0);

  Future<void> open() async {
    final uid = userId;
    if (uid == null) {
      error = 'Not signed in';
      loading = false;
      notifyListeners();
      return;
    }
    itinerary = ItineraryDoc(tripId, nodeId: uid.substring(0, 8));
    try {
      trip = await _repo.trip(tripId);
      await _loadMembers();
      final rows = await _db.from('waypoints').select().eq('trip_id', tripId);
      itinerary.mergeAll(rows.map(Waypoint.fromRow));
      final msgs = await _db
          .from('messages')
          .select('*, profiles:sender_id(display_name)')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .limit(100);
      messages
        ..clear()
        ..addAll(msgs.map(ChatMessage.fromRow).toList().reversed);
      for (final p in await _repo.lastKnownPositions(tripId)) {
        _reported[p.memberId] = p;
      }
    } catch (e) {
      // Opening a trip with no signal: carry on with whatever the outbox and
      // mesh can provide. The map, GPS and offline tiles still work.
      error = friendlyError(e);
      link = LinkMode.isolated;
    }

    _outbox = Outbox(_db, tripId);
    await _outbox!.load();
    pendingWrites = _outbox!.length;

    if (me != null) _startLive(me!.id);
    _subs.add(Connectivity().onConnectivityChanged.listen((_) => _onConnectivity()));
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    loading = false;
    notifyListeners();
  }

  Future<void> _loadMembers() async {
    final list = await _repo.members(tripId);
    members = {for (final m in list) m.id: m};
    me = list.where((m) => m.userId == userId).firstOrNull;
  }

  void _startLive(String memberId) {
    final ch = ConvoyChannel(_db, tripId: tripId, memberId: memberId)..connect();
    channel = ch;
    _subs.addAll([
      ch.positions.listen(_acceptPosition),
      ch.waypoints.listen((w) {
        if (itinerary.merge(w)) notifyListeners();
      }),
      ch.messages.listen(_acceptMessage),
      ch.membersChanged.listen((_) async {
        await _loadMembers();
        notifyListeners();
      }),
      ch.tripChanged.listen((t) {
        trip = t;
        notifyListeners();
      }),
      ch.online.listen((ids) {
        online = ids;
        ptt?.syncPeers(ids);
        notifyListeners();
      }),
      ch.status.listen((_) => _onConnectivity()),
    ]);

    final g = GpsService(memberId: memberId);
    gps = g;
    _subs.add(g.positions.listen(_onOwnFix));
    g.start().then((p) {
      gpsPermission = p;
      notifyListeners();
    });

    ptt = PttService(selfId: memberId, signaller: ch);
  }

  void _acceptPosition(VehiclePosition p) {
    final prev = _reported[p.memberId];
    // Same fix may arrive via cloud and mesh; keep the newest.
    if (prev != null && !p.timestamp.isAfter(prev.timestamp)) return;
    _reported[p.memberId] = p;
    notifyListeners();
  }

  /// Entry point for positions heard over the mesh.
  void acceptMeshPosition(VehiclePosition p) => _acceptPosition(p);

  void _acceptMessage(ChatMessage m) {
    final i = messages.indexWhere((x) => x.id == m.id);
    final named = m.senderName == null
        ? ChatMessage(
            id: m.id,
            tripId: m.tripId,
            senderId: m.senderId,
            senderName: members.values.where((x) => x.userId == m.senderId).firstOrNull?.displayName,
            body: m.body,
            kind: m.kind,
            createdAt: m.createdAt,
            viaMesh: m.viaMesh,
          )
        : m;
    if (i >= 0) {
      messages[i] = named;
    } else {
      messages.add(named);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    notifyListeners();
  }

  /// Entry point for chat and itinerary rows heard over the mesh.
  void acceptMeshMessage(ChatMessage m) => _acceptMessage(m.copyWith(viaMesh: true));

  void acceptMeshWaypoint(Waypoint w) {
    if (itinerary.merge(w)) {
      // Relay into the cloud on behalf of a peer that has no signal. RLS
      // requires the writer's own id on the row; the HLC is preserved, so the
      // relayed write still loses to any newer edit.
      _queue(OutboxItem('waypoints', w.copyWith(updatedBy: userId).toRow()));
      notifyListeners();
    }
  }

  Future<void> _onOwnFix(VehiclePosition p) async {
    _reported[p.memberId] = p;
    notifyListeners();
    final now = DateTime.now();
    if (now.difference(_lastBroadcast) < const Duration(seconds: 1)) return;
    _lastBroadcast = now;

    final sentCloud = await (channel?.sendPosition(p) ?? Future.value(false));
    if (meshSendPosition != null) {
      // The mesh carries positions even when the cloud is up: nearby cars
      // update faster and the mesh stays warm for when the signal drops.
      unawaited(meshSendPosition!(p));
    }
    if (sentCloud && now.difference(_lastPersist) > const Duration(seconds: 30)) {
      _lastPersist = now;
      unawaited(_repo.saveLastKnown(tripId, p).catchError((_) {}));
    }
  }

  void _tick() {
    _updateLink();
    // Re-render so dead-reckoned vehicles keep moving between reports.
    notifyListeners();
  }

  void _updateLink() {
    final live = channel?.isLive ?? false;
    final next = live
        ? LinkMode.cloud
        : (meshHasPeers?.call() ?? false)
            ? LinkMode.mesh
            : LinkMode.isolated;
    if (next != link) {
      link = next;
      notifyListeners();
    }
  }

  Future<void> _onConnectivity() async {
    _updateLink();
    if (channel?.isLive ?? false) {
      final sent = await _outbox?.flush() ?? 0;
      pendingWrites = _outbox?.length ?? 0;
      if (sent > 0) notifyListeners();
    }
  }

  Future<void> _queue(OutboxItem item) async {
    await _outbox?.add(item);
    pendingWrites = _outbox?.length ?? 0;
    await _onConnectivity();
  }

  // ───────────────────────────── itinerary ────────────────────────────

  Future<void> _publish(Iterable<Waypoint> rows) async {
    notifyListeners();
    for (final w in rows) {
      await _queue(OutboxItem('waypoints', w.toRow()));
      if (meshSendWaypoint != null) unawaited(meshSendWaypoint!(w));
    }
  }

  Future<void> addStop({
    required String name,
    required GeoPoint location,
    WaypointKind kind = WaypointKind.waypoint,
    String? afterId,
    DateTime? arrival,
    String notes = '',
  }) =>
      _publish([
        itinerary.insert(
          id: _uuid.v4(),
          name: name,
          location: location,
          kind: kind,
          afterId: afterId ?? itinerary.waypoints.lastOrNull?.id,
          plannedArrival: arrival,
          notes: notes,
          userId: userId,
        ),
      ]);

  Future<void> editStop(String id, Waypoint Function(Waypoint) edit) =>
      _publish([itinerary.update(id, edit, userId: userId)]);

  Future<void> removeStop(String id) => _publish([itinerary.remove(id, userId: userId)]);

  Future<void> moveStop(String id, String? afterId) =>
      _publish([itinerary.move(id, afterId, userId: userId)]);

  Future<void> shiftSchedule(String fromId, Duration delta) async {
    final changed = itinerary.shiftSchedule(fromId, delta, userId: userId);
    await _publish(changed);
    if (changed.isNotEmpty) {
      final mins = delta.inMinutes;
      await sendMessage('${mins >= 0 ? 'Running $mins min late' : 'Running ${-mins} min early'} — schedule updated',
          kind: 'quick');
    }
  }

  // ─────────────────────────────── chat ───────────────────────────────

  Future<void> sendMessage(String body, {String kind = 'text'}) async {
    final uid = userId;
    if (uid == null || body.trim().isEmpty) return;
    final m = ChatMessage(
      id: _uuid.v4(),
      tripId: tripId,
      senderId: uid,
      senderName: me?.displayName,
      body: body.trim(),
      kind: kind,
      createdAt: DateTime.now(),
      pending: true,
    );
    _acceptMessage(m);
    if (meshSendChat != null) unawaited(meshSendChat!(m));
    await _queue(OutboxItem('messages', m.toRow()));
    final i = messages.indexWhere((x) => x.id == m.id);
    // Delivered once the outbox no longer holds it.
    if (i >= 0 && pendingWrites == 0) {
      messages[i] = messages[i].copyWith(pending: false);
      notifyListeners();
    }
  }

  // ─────────────────────────────── lead ───────────────────────────────

  Future<void> setLead(String memberId) async {
    await _repo.setLead(tripId, memberId);
    trip = await _repo.trip(tripId);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    gps?.dispose();
    ptt?.dispose();
    channel?.dispose();
    super.dispose();
  }
}
