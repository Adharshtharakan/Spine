import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/geo/geo.dart';
import '../data/models/convoy_event.dart';
import '../data/models/social.dart';
import '../data/models/trip.dart';
import '../data/models/waypoint.dart';
import '../data/repositories/trip_repository.dart';
import '../services/location/gps_service.dart';
import '../services/offline/outbox.dart';
import '../services/offline/trip_cache.dart';
import '../services/planning/planning_services.dart';
import '../services/push/push_service.dart';
import '../services/realtime/convoy_channel.dart';
import '../services/edge/edge_client.dart';
import '../services/tracking/predictor.dart';
import '../services/tracking/convoy_events.dart';
import '../services/tracking/convoy_watch.dart';
import '../services/tracking/lead_vehicle.dart';
import '../services/tracking/safety_watch.dart';
import '../services/voice/ptt_service.dart';
import '../sync/itinerary_doc.dart';

/// How the convoy is currently being kept in sync, best first.
enum LinkMode {
  /// Supabase Realtime is live.
  cloud,

  /// Realtime keeps dropping but small HTTP requests get through (2G/EDGE,
  /// fringe coverage): positions, chat and plan are polled every 15 s.
  weak,

  /// No internet; other cars are heard over the LoRa radio mesh (km range).
  radio,

  /// No internet; only cars close by, over Bluetooth / Wi-Fi Direct.
  nearby,

  /// Nothing: own GPS still plots, others are predicted from their last fix.
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

  /// Hooks for the off-grid links, set by [attachMesh].
  Future<void> Function(VehiclePosition p)? meshSendPosition;
  Future<void> Function(ChatMessage m)? meshSendChat;
  Future<void> Function(Waypoint w)? meshSendWaypoint;
  Future<void> Function(ConvoyEvent e)? meshSendEvent;
  Future<void> Function(ConvoyEvent e)? meshForwardEvent;

  /// Gateway: push cloud-side positions / chat onto the radio.
  Future<void> Function(VehiclePosition p)? meshForwardPosition;
  Future<void> Function(ChatMessage m)? meshForwardChat;

  /// Peers currently reachable on a link (`lora`, `nearby`).
  int Function(String transport)? meshPeersOn;

  /// Positions heard off-grid, waiting to be relayed into the cloud.
  final Map<String, VehiclePosition> _toRelay = {};
  final Map<String, DateTime> _gatewayBroadcastAt = {};
  DateTime? _lastPollOk;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _offlineSince;
  String? _waypointCursor;
  bool _polling = false;

  static const _resolver = LeadVehicleResolver();
  static const _predictor = ConvoyPredictor();

  // ─────────────────────────── convoy watch ───────────────────────────

  final ConvoyWatch _watch = ConvoyWatch();

  /// Alerts currently shown on the map (newest first, auto-expiring).
  final List<ConvoyAlert> alerts = [];
  final _alertCtrl = StreamController<ConvoyAlert>.broadcast();

  /// Every new alert, for the spoken announcer.
  Stream<ConvoyAlert> get alertStream => _alertCtrl.stream;

  static const alertLifetime = Duration(seconds: 45);

  void _raise(ConvoyAlert a) {
    alerts.removeWhere((x) => x.key == a.key);
    alerts.insert(0, a);
    if (alerts.length > 3) alerts.removeRange(3, alerts.length);
    if (!_alertCtrl.isClosed) _alertCtrl.add(a);
    notifyListeners();
  }

  void dismissAlert(ConvoyAlert a) {
    alerts.remove(a);
    notifyListeners();
  }

  /// Set by a passenger to unlock typing for this trip.
  bool passengerMode = false;

  /// True when this phone is in a moving vehicle that someone is driving:
  /// typing is paused (quick replies and push-to-talk stay available). The
  /// navigator is a passenger by definition.
  bool get drivingLock {
    if (passengerMode || me?.convoyRole == ConvoyRole.navigator || !(me?.hasVehicle ?? false)) return false;
    final mine = me == null ? null : _reported[me!.id];
    return mine != null && mine.speedMps > 15 / 3.6 && DateTime.now().difference(mine.timestamp) < const Duration(seconds: 20);
  }

  void _evaluateWatch() {
    final now = DateTime.now();
    alerts.removeWhere((a) => now.difference(a.at) > alertLifetime);
    final labels = {for (final m in members.values) m.id: m.vehicleLabel ?? m.displayName};
    final vehicles = {
      for (final e in _reported.entries)
        if (members[e.key]?.hasVehicle ?? true) e.key: e.value,
    };
    final selfOnline = _cloudReachable || (meshPeersOn?.call('lora') ?? 0) + (meshPeersOn?.call('nearby') ?? 0) > 0;
    for (final a in _watch.evaluate(
      now: now,
      reported: vehicles,
      standings: _resolver.standings(lead: lead, positions: vehicles, route: routeLine, now: now),
      route: routeLine,
      stops: itinerary.waypoints,
      labels: labels,
      selfId: me?.id,
      selfOnline: selfOnline,
    )) {
      _raise(a);
    }
    _evaluateSafety(now, vehicles);
  }


  // ───────────────────────── safety and planning ──────────────────────

  /// The convoy event log (SOS, hazards, regroup, headcount), oldest first.
  final List<ConvoyEvent> events = [];
  ConvoyEventState get eventState => ConvoyEventState.from(events, DateTime.now());

  final DriverNudges _nudges = DriverNudges();
  final SweepWatch _sweepWatch = SweepWatch();
  final HazardAhead _hazardAhead = HazardAhead();

  /// Speaks a reply (voice commands); set by the announcer.
  Future<void> Function(String text)? speak;

  /// Set when the crash detector suspects an accident; the trip screen shows
  /// a 30-second countdown and raises an SOS unless cancelled.
  final crashAlarm = ValueNotifier<DateTime?>(null);

  /// Forecast at each stop's planned arrival (waypoint id → forecast).
  Map<String, StopForecast> weather = const {};
  DateTime _weatherAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _weatherKey;
  final Set<String> _weatherAnnounced = {};

  /// Toll plazas on the route (null until fetched).
  List<TollPlaza>? tolls;
  String? _tollsKey;
  DateTime _tollsAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Distance this phone has driven during the trip, for the fuel range.
  double _odometerM = 0;
  VehiclePosition? _lastOdoFix;

  /// Range left as the driver last entered it, and the odometer then.
  double? _rangeSetKm;
  double _rangeSetOdoM = 0;
  DateTime? _fuelWarnedAt;

  String? get sweepId => members.values.where((m) => m.convoyRole == ConvoyRole.sweep).firstOrNull?.id;

  /// Range left now: what was entered minus what has been driven since.
  double? get rangeLeftKm => _rangeSetKm == null ? null : (_rangeSetKm! - (_odometerM - _rangeSetOdoM) / 1000).clamp(0, 5000).toDouble();

  void setRangeLeft(double km) {
    _rangeSetKm = km;
    _rangeSetOdoM = _odometerM;
    _fuelWarnedAt = null;
    unawaited(_saveSnapshot());
    notifyListeners();
  }

  /// "Next fuel in 140 km, your range is 90 km."
  FuelStatus? get fuelStatus {
    final range = rangeLeftKm;
    final mine = me == null ? null : _reported[me!.id];
    final route = routeLine;
    if (range == null || route.length < 2) return null;
    final along = mine == null ? 0.0 : Geo.projectOntoRoute(route, mine.point).alongMeters / 1000;
    return FuelStatus.evaluate(
      rangeKm: range,
      myAlongKm: along,
      fuelStops: [
        for (final w in itinerary.waypoints)
          if (w.kind == WaypointKind.fuel) (name: w.name, alongKm: Geo.projectOntoRoute(route, w.location).alongMeters / 1000),
      ],
      routeKm: Geo.routeLength(route) / 1000,
    );
  }

  /// How far each car is from the regroup point.
  List<RegroupEta> get regroupEtas {
    final pin = eventState.regroup?.location;
    if (pin == null) return const [];
    final vehicles = {
      for (final e in positions.entries)
        if (members[e.key]?.hasVehicle ?? true) e.key: e.value,
    };
    return RegroupEta.compute(
      point: pin,
      positions: vehicles,
      route: routeLine,
      averageSpeedMps: {for (final e in _avgSpeed.entries) e.key: e.value.value},
    );
  }

  String _label(String memberId) {
    final m = members[memberId];
    return m?.vehicleLabel ?? m?.displayName ?? 'A car';
  }

  void _evaluateSafety(DateTime now, Map<String, VehiclePosition> vehicles) {
    final mine = me == null ? null : _reported[me!.id];
    final others = [
      for (final p in vehicles.values)
        if (p.memberId != me?.id && p.speedMps > 3 && p.age(now) < const Duration(minutes: 1)) p.speedMps * 3.6,
    ]..sort();
    final median = others.isEmpty ? null : others[others.length ~/ 2];
    if (me?.hasVehicle ?? false) {
      for (final a in _nudges.evaluate(now: now, me: mine, convoyKmh: median)) {
        _raise(a);
      }
    }
    if (me != null && sweepId == me!.id) {
      final labels = {for (final m in members.values) m.id: m.vehicleLabel ?? m.displayName};
      for (final a in _sweepWatch.evaluate(now: now, sweepId: me!.id, standings: standings, labels: labels)) {
        _raise(a);
      }
    }
    for (final a in _hazardAhead.evaluate(now: now, me: mine, hazards: eventState.hazards, route: routeLine)) {
      _raise(a);
    }
    final fuel = fuelStatus;
    if (fuel != null && fuel.warn && (_fuelWarnedAt == null || now.difference(_fuelWarnedAt!) > const Duration(minutes: 30))) {
      _fuelWarnedAt = now;
      final next = fuel.nextFuelKm == null
          ? 'No fuel stop is planned before the destination'
          : 'Next fuel is ${fuel.nextFuelName} in ${fuel.nextFuelKm!.round()} km';
      _raise(ConvoyAlert(
        kind: AlertKind.fuel,
        memberId: me?.id,
        message: '$next; your range is ${fuel.rangeKm.round()} km.',
        spoken: '$next, and your range is ${fuel.rangeKm.round()} kilometres. Plan a fuel stop.',
        at: now,
      ));
    }
  }

  void _odometer(VehiclePosition p) {
    final last = _lastOdoFix;
    _lastOdoFix = p;
    if (last == null || p.accuracyM > 50) return;
    final d = Geo.distanceMeters(last.point, p.point);
    // Ignore GPS jitter while parked and impossible jumps.
    final dt = p.timestamp.difference(last.timestamp).inMilliseconds / 1000;
    if (d < 5 || dt <= 0 || d / dt > 70) return;
    _odometerM += d;
  }

  // Weather at each stop, refreshed every 30 minutes while online.
  Future<void> _refreshWeather() async {
    final timed = itinerary.waypoints.where((w) => w.plannedArrival != null).toList();
    final key = [for (final w in timed) '${w.id}@${w.plannedArrival!.millisecondsSinceEpoch}'].join(',');
    final now = DateTime.now();
    if (timed.isEmpty || (key == _weatherKey && now.difference(_weatherAt) < const Duration(minutes: 30))) return;
    if (now.difference(_weatherAt) < const Duration(minutes: 2)) return;
    _weatherAt = now;
    try {
      weather = await WeatherService(_db).forStops(timed);
      _weatherKey = key;
      // Warn once about the next stop with bad weather in the next 6 hours.
      for (final w in timed) {
        final f = weather[w.id];
        final worst = f?.worst;
        if (worst == null || w.plannedArrival!.difference(now) > const Duration(hours: 6)) continue;
        if (!_weatherAnnounced.add('${w.id}:${worst.name}')) break;
        _raise(ConvoyAlert(
          kind: AlertKind.weather,
          memberId: null,
          tag: w.id,
          message: '${worst.label} at ${w.name} around ${_hm(w.plannedArrival!)}.',
          spoken: '${worst.label} at ${w.name}. Drive carefully.',
          at: now,
        ));
        break;
      }
      notifyListeners();
    } catch (_) {
      // Offline or the Worker isn't configured: no forecast.
    }
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _refreshTolls() async {
    final route = routeLine;
    if (route.length < 2 || !identical(route, _road) || _tollsKey == _roadKey) return;
    if (DateTime.now().difference(_tollsAttempt) < const Duration(minutes: 5)) return;
    _tollsAttempt = DateTime.now();
    try {
      tolls = await TollService(_db).onRoute(route);
      _tollsKey = _roadKey;
      notifyListeners();
    } catch (_) {}
  }

  /// Fuel and toll estimate for one car over the whole route.
  TripCost costFor(TripMember m) => TripCost.estimate(
        distanceKm: Geo.routeLength(routeLine) / 1000,
        kmpl: m.fuelKmpl,
        fuelPrice: trip?.fuelPrice,
        plazas: tolls?.length ?? 0,
        tollPerPlaza: trip?.tollPerPlaza,
      );

  // ── raising events ──

  Future<ConvoyEvent?> _raiseEvent(EventKind kind, {GeoPoint? at, Map<String, dynamic> payload = const {}}) async {
    final m = me;
    if (m == null) return null;
    final e = ConvoyEvent(
      id: _uuid.v4(),
      tripId: tripId,
      memberId: m.id,
      kind: kind,
      location: at ?? _reported[m.id]?.point,
      payload: payload,
      createdAt: DateTime.now(),
    );
    _acceptEvent(e, local: true);
    if (meshSendEvent != null) unawaited(meshSendEvent!(e));
    await _queue(OutboxItem('trip_events', e.toRow()));
    return e;
  }

  /// SOS: the whole convoy is alerted with this car's location, over the
  /// cloud, push and the radio.
  Future<ConvoyEvent?> raiseSos({String? note}) async {
    final e = await _raiseEvent(EventKind.sos, payload: {'note': ?note});
    if (e != null) {
      unawaited(PushService.notifyParty(_db,
          tripId: tripId,
          kind: 'sos',
          title: 'SOS: ${_label(e.memberId)} needs help',
          body: note ?? 'Open DriveSync to see where they are.'));
    }
    return e;
  }

  Future<void> cancelSos() async {
    final mine = eventState.sos[me?.id];
    if (mine != null) await _raiseEvent(EventKind.sosClear, payload: {'ref': mine.id});
  }

  /// Someone else's SOS handled (they're safe, help arrived).
  Future<void> resolveSos(ConvoyEvent sos) => _raiseEvent(EventKind.sosClear, payload: {'ref': sos.id}).then((_) {});

  Future<void> reportHazard(HazardType type, {GeoPoint? at}) async {
    final e = await _raiseEvent(EventKind.hazard, at: at, payload: {'type': type.name});
    if (e != null) {
      unawaited(PushService.notifyParty(_db,
          tripId: tripId, kind: 'hazard', title: '${type.label} reported', body: 'By ${_label(e.memberId)}. It is marked on the map.'));
    }
  }

  Future<void> clearHazard(ConvoyEvent hazard) => _raiseEvent(EventKind.hazardClear, payload: {'ref': hazard.id}).then((_) {});

  Future<void> setRegroup(GeoPoint at, {String? name}) async {
    await _raiseEvent(EventKind.regroup, at: at, payload: {'note': ?name});
    unawaited(PushService.notifyParty(_db,
        tripId: tripId, kind: 'regroup', title: 'Regroup point set', body: name == null ? 'Open the map for directions.' : 'Meet at $name.'));
  }

  Future<void> clearRegroup() async {
    final r = eventState.regroup;
    if (r != null) await _raiseEvent(EventKind.regroupClear, payload: {'ref': r.id});
  }

  Future<void> startHeadcount() async {
    await _raiseEvent(EventKind.headcount);
    unawaited(PushService.notifyParty(_db,
        tripId: tripId, kind: 'headcount', title: 'Back in your car?', body: 'Tap "Ready to go" in DriveSync.'));
  }

  Future<void> markReady() => _raiseEvent(EventKind.ready).then((_) {});

  Future<void> sayGo() => _raiseEvent(EventKind.go).then((_) {});

  Future<void> setConvoyRole(String memberId, ConvoyRole? role) async {
    await _repo.setConvoyRole(memberId, role);
    await _loadMembers();
    notifyListeners();
  }

  Future<void> updateCosts({double? fuelPrice, double? tollPerPlaza}) async {
    await _repo.updateCosts(tripId, fuelPrice: fuelPrice, tollPerPlaza: tollPerPlaza);
    trip = await _repo.trip(tripId);
    notifyListeners();
  }

  // ── receiving events ──

  void _acceptEvent(ConvoyEvent e, {bool local = false}) {
    if (events.any((x) => x.id == e.id)) return;
    final before = eventState;
    events.add(e);
    events.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (events.length > 500) events.removeAt(0);
    if (!local && e.memberId != me?.id) _announceEvent(e, before);
    notifyListeners();
  }

  void _announceEvent(ConvoyEvent e, ConvoyEventState before) {
    final now = DateTime.now();
    final who = _label(e.memberId);
    if (now.difference(e.createdAt) > const Duration(hours: 1)) return;
    switch (e.kind) {
      case EventKind.sos:
        final mine = me == null ? null : _reported[me!.id];
        final where = mine != null && e.location != null
            ? ', ${Geo.formatDistance(Geo.distanceMeters(mine.point, e.location!))} ${Geo.compass(Geo.bearingDeg(mine.point, e.location!))} of you'
            : '';
        final msg = 'SOS: $who needs help$where.${e.note == null ? '' : ' ${e.note}'}';
        _raise(ConvoyAlert(kind: AlertKind.sos, memberId: e.memberId, message: msg, spoken: 'Emergency. $who needs help.', at: now));
        unawaited(PushService.show('sos', 'SOS: $who needs help', e.note ?? 'Open DriveSync to see where they are.', tripId: tripId));
      case EventKind.sosClear:
        final sos = before.sos.values.where((x) => x.id == e.ref || (e.ref == null && x.memberId == e.memberId)).firstOrNull;
        if (sos != null) {
          final name = _label(sos.memberId);
          _raise(ConvoyAlert(kind: AlertKind.sos, memberId: sos.memberId, message: '$name is OK. SOS cancelled.', at: now));
        }
      case EventKind.regroup:
        _raise(ConvoyAlert(
          kind: AlertKind.regroup,
          memberId: e.memberId,
          message: '$who set a regroup point${e.note == null ? '' : ' at ${e.note}'}.',
          spoken: 'Regroup point set${e.note == null ? '' : ' at ${e.note}'}.',
          at: now,
        ));
      case EventKind.headcount:
        _raise(ConvoyAlert(
          kind: AlertKind.headcount,
          memberId: e.memberId,
          message: 'Headcount: tap "Ready to go" when you are back in your car.',
          spoken: 'Headcount. Tap ready to go when you are back in your car.',
          at: now,
        ));
      case EventKind.go:
        _raise(ConvoyAlert(kind: AlertKind.headcount, memberId: e.memberId, message: 'Everyone is in. The convoy is moving.', at: now));
      case EventKind.hazard:
        // Announced to cars approaching it (HazardAhead), not to everyone.
        break;
      case EventKind.hazardClear || EventKind.regroupClear || EventKind.ready:
        break;
    }
  }

  /// Events heard over the radio / phone mesh; relayed into the cloud by
  /// whichever car has signal.
  void acceptMeshEvent(ConvoyEvent e) {
    final known = events.any((x) => x.id == e.id);
    _acceptEvent(e);
    if (!known && e.memberId != me?.id) _queue(OutboxItem('relay_event', e.toRow()));
  }

  Future<void> _loadEvents() async {
    final since = DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String();
    final rows = await _db.from('trip_events').select().eq('trip_id', tripId).gte('created_at', since).order('created_at').limit(500);
    for (final r in rows) {
      final e = ConvoyEvent.fromRow(r);
      if (e != null && !events.any((x) => x.id == e.id)) events.add(e);
    }
  }

  /// Announces edits other people make to the plan.
  void _mergeRemoteWaypoint(Waypoint w) {
    final before = itinerary[w.id];
    if (!itinerary.merge(w)) return;
    if (w.updatedBy != null && w.updatedBy != userId) {
      final by = members.values.where((m) => m.userId == w.updatedBy).firstOrNull?.displayName;
      final a = ConvoyWatch.describePlanChange(before, w, by: by, now: DateTime.now());
      if (a != null) _raise(a);
    }
    notifyListeners();
  }

  /// Recent fixes per member (≈10 min), for smoothed speed and for
  /// anchoring a silent car to a convoy-mate.
  final Map<String, List<VehiclePosition>> _history = {};

  /// Road geometry through the stops, fetched while online and cached with
  /// the trip so prediction follows real roads offline too.
  List<GeoPoint>? _road;
  String? _roadKey;
  RoadSpeeds? _roadSpeeds;

  /// Each car's average moving speed over the trip, persisted.
  final Map<String, AverageSpeed> _avgSpeed = {};
  DateTime _roadAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  String get _stopsKey => itinerary.route.map((p) => '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}').join(';');

  /// The line everything is measured along: real roads when known,
  /// straight segments between stops otherwise.
  List<GeoPoint> get routeLine => (_road != null && _roadKey == _stopsKey) ? _road! : itinerary.route;

  String? get userId => _db.auth.currentUser?.id;

  /// For services that act on the trip's behalf (Worker calls).
  SupabaseClient get db => _db;
  bool get isOwner => trip?.ownerId == userId;

  /// Positions to draw: fresh reports as-is; cars that went silent are
  /// predicted (see [ConvoyPredictor]) so the map never just freezes.
  Map<String, VehiclePosition> get positions {
    final now = DateTime.now();
    final route = routeLine;
    final stops = itinerary.waypoints;
    final labels = {for (final m in members.values) m.id: m.vehicleLabel ?? m.displayName};
    return {
      for (final e in _reported.entries)
        e.key: (e.key != me?.id && e.value.age(now) > const Duration(seconds: 30))
            ? _predictor.predict(
                last: e.value,
                route: route,
                history: _history,
                latest: _reported,
                stops: stops,
                now: now,
                labels: labels,
                averageSpeed: _avgSpeed[e.key]?.value,
                roadSpeedAt: _road != null && _roadKey == _stopsKey ? _roadSpeeds?.at : null,
              )
            : e.value,
    };
  }

  LeadResult? get lead {
    final r = _resolver.resolve(designatedMemberId: trip?.leadMemberId, positions: _reported, route: routeLine);
    if (r == null || r.reason != LeadReason.designatedSilent || routeLine.length < 2) return r;
    // A briefly silent lead is measured where it probably is now.
    final est = positions[r.memberId];
    return est == null ? r : LeadResult(r.memberId, r.reason, Geo.projectOntoRoute(routeLine, est.point).alongMeters);
  }

  List<ConvoyStanding> get standings => _resolver.standings(lead: lead, positions: _reported, route: routeLine);

  Waypoint? get nextStop {
    final route = routeLine;
    if (route.length < 2) return itinerary.waypoints.firstOrNull;
    final leadAlong = lead?.alongMeters ?? 0;
    for (final w in itinerary.waypoints) {
      if (Geo.projectOntoRoute(route, w.location).alongMeters > leadAlong + 150) return w;
    }
    return null;
  }

  /// The last real report from a member (not a prediction).
  VehiclePosition? lastReported(String memberId) => _reported[memberId];

  void _remember(VehiclePosition p) {
    final h = _history.putIfAbsent(p.memberId, () => []);
    if (h.isNotEmpty && !p.timestamp.isAfter(h.last.timestamp)) return;
    h.add(p);
    _avgSpeed.putIfAbsent(p.memberId, AverageSpeed.new).add(p);
    final cutoff = p.timestamp.subtract(const Duration(minutes: 10));
    while (h.length > 1 && h.first.timestamp.isBefore(cutoff)) {
      h.removeAt(0);
    }
    if (h.length > 300) h.removeAt(0);
  }

  /// Fetches road geometry when the stops change and we are online.
  Future<void> _refreshRoad() async {
    final key = _stopsKey;
    if (itinerary.route.length < 2 || key == _roadKey) return;
    if (DateTime.now().difference(_roadAttempt) < const Duration(minutes: 1)) return;
    _roadAttempt = DateTime.now();
    try {
      final res = await EdgeClient(_db).post('/route', {
        'points': [for (final p in itinerary.route.take(50)) [p.lat, p.lng]],
      });
      _road = [
        for (final c in res['geometry'] as List) GeoPoint((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      ];
      _roadKey = key;
      _roadSpeeds = RoadSpeeds.fromLegs([
        for (final l in (res['legs'] as List? ?? const []))
          (distanceM: (l['distance_m'] as num).toDouble(), durationS: (l['duration_s'] as num).toDouble()),
      ]);
      unawaited(_saveSnapshot());
      notifyListeners();
    } catch (_) {
      // Offline or no route: straight segments keep working.
    }
  }

  Future<void> open() async {
    final uid = userId;
    if (uid == null) {
      error = 'Not signed in';
      loading = false;
      notifyListeners();
      return;
    }
    itinerary = ItineraryDoc(tripId, nodeId: uid.substring(0, 8));
    final cache = TripCache(tripId);
    final cached = await cache.load();
    if (cached?['road'] is List && cached?['road_key'] is String) {
      _road = [for (final c in cached!['road'] as List) GeoPoint((c[0] as num).toDouble(), (c[1] as num).toDouble())];
      _roadKey = cached['road_key'] as String;
      if (cached['road_speeds'] is List) _roadSpeeds = RoadSpeeds.fromJson(cached['road_speeds'] as List);
    }
    if (cached != null) {
      _odometerM = (cached['odometer_m'] as num?)?.toDouble() ?? 0;
      _rangeSetKm = (cached['range_set_km'] as num?)?.toDouble();
      _rangeSetOdoM = (cached['range_set_odo_m'] as num?)?.toDouble() ?? 0;
    }
    if (cached?['avg_speed'] is Map) {
      (cached!['avg_speed'] as Map).forEach((k, v) => _avgSpeed[k as String] = AverageSpeed((v as num).toDouble()));
    }
    try {
      trip = await _repo.trip(tripId);
      await _loadMembers();
      final rows = await _db.from('waypoints').select().eq('trip_id', tripId);
      itinerary.mergeAll(rows.map(Waypoint.fromRow));
      for (final r in rows) {
        final u = r['updated_at'] as String?;
        if (u != null && (_waypointCursor == null || u.compareTo(_waypointCursor!) > 0)) _waypointCursor = u;
      }
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
      await _loadEvents();
      unawaited(_saveSnapshot());
    } catch (e) {
      // Opened with no signal: restore the last snapshot so the map, GPS,
      // offline tiles and the mesh all still work.
      final snap = cached;
      if (snap != null) {
        _restoreSnapshot(snap);
      } else {
        error = friendlyError(e);
      }
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

  Future<void> _saveSnapshot() => TripCache(tripId).save({
        'trip': trip?.toRow(),
        'members': [for (final m in members.values) m.toRow()],
        'waypoints': [for (final w in itinerary.allRows) w.toRow()],
        'messages': [for (final m in messages.where((m) => !m.pending).take(100)) m.toRow()],
        'positions': [for (final p in _reported.values) p.toJson()],
        'road': [for (final p in _road ?? const <GeoPoint>[]) [p.lat, p.lng]],
        'road_key': _roadKey,
        'road_speeds': _roadSpeeds?.toJson(),
        'avg_speed': {
          for (final e in _avgSpeed.entries)
            if (e.value.value != null) e.key: e.value.value,
        },
        'events': [for (final e in events.take(200)) e.toRow()],
        'odometer_m': _odometerM,
        'range_set_km': _rangeSetKm,
        'range_set_odo_m': _rangeSetOdoM,
      });

  void _restoreSnapshot(Map<String, dynamic> snap) {
    List<Map<String, dynamic>> rows(String k) =>
        [for (final r in (snap[k] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    if (snap['trip'] != null) trip = Trip.fromRow(Map<String, dynamic>.from(snap['trip'] as Map));
    members = {for (final r in rows('members')) r['id'] as String: TripMember.fromRow(r)};
    me = members.values.where((m) => m.userId == userId).firstOrNull;
    itinerary.mergeAll(rows('waypoints').map(Waypoint.fromRow));
    messages
      ..clear()
      ..addAll(rows('messages').map(ChatMessage.fromRow));
    for (final r in rows('positions')) {
      final p = VehiclePosition.fromJson(r);
      _reported[p.memberId] = p;
    }
    for (final r in rows('events')) {
      final e = ConvoyEvent.fromRow(r);
      if (e != null) events.add(e);
    }
  }

  final List<Future<void> Function()> _disposers = [];

  /// Lets attached subsystems (the mesh) clean up with the session.
  void addDisposer(Future<void> Function() d) => _disposers.add(d);

  Future<void> _loadMembers() async {
    final list = await _repo.members(tripId);
    members = {for (final m in list) m.id: m};
    me = list.where((m) => m.userId == userId).firstOrNull;
  }

  void _startLive(String memberId) {
    final ch = ConvoyChannel(_db, tripId: tripId, memberId: memberId)..connect();
    channel = ch;
    _subs.addAll([
      ch.positions.listen((p) {
        _acceptPosition(p);
        // Gateway: cars on the radio with no signal learn about this car.
        if (meshForwardPosition != null) unawaited(meshForwardPosition!(p));
      }),
      ch.waypoints.listen(_mergeRemoteWaypoint),
      ch.events.listen((e) {
        _acceptEvent(e);
        // Gateway: radio-only cars hear an SOS raised by a car with signal.
        if (meshForwardEvent != null) unawaited(meshForwardEvent!(e));
      }),
      ch.messages.listen((m) {
        _acceptMessage(m);
        if (meshForwardChat != null) unawaited(meshForwardChat!(m));
      }),
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
    _remember(p);
    notifyListeners();
  }

  /// Entry point for positions heard over the radio / phone mesh. If this
  /// car has any signal it acts as a gateway and passes them to the cloud.
  void acceptMeshPosition(VehiclePosition p) {
    _acceptPosition(p);
    if (p.memberId == me?.id) return;
    _toRelay[p.memberId] = p;
    final live = channel?.isLive ?? false;
    final last = _gatewayBroadcastAt[p.memberId];
    if (live && (last == null || DateTime.now().difference(last) > const Duration(seconds: 5))) {
      _gatewayBroadcastAt[p.memberId] = DateTime.now();
      unawaited(channel!.sendPosition(p));
    }
  }

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

  /// Entry point for chat and itinerary rows heard over the mesh. Relayed
  /// into the cloud (idempotently) by whichever car has signal first.
  void acceptMeshMessage(ChatMessage m) {
    final known = messages.any((x) => x.id == m.id);
    _acceptMessage(m.copyWith(viaMesh: true));
    if (!known && m.senderId != userId) _queue(OutboxItem('relay_message', m.toRow()));
  }

  void acceptMeshWaypoint(Waypoint w) {
    final before = itinerary[w.id];
    if (itinerary.merge(w)) {
      if (w.updatedBy != userId) {
        final by = members.values.where((m) => m.userId == w.updatedBy).firstOrNull?.displayName;
        final a = ConvoyWatch.describePlanChange(before, w, by: by, now: DateTime.now());
        if (a != null) _raise(a);
      }
      // Relay into the cloud on behalf of a peer that has no signal. RLS
      // requires the writer's own id on the row; the HLC is preserved, so the
      // relayed write still loses to any newer edit.
      _queue(OutboxItem('waypoints', w.copyWith(updatedBy: userId).toRow()));
      notifyListeners();
    }
  }

  Future<void> _onOwnFix(VehiclePosition p) async {
    _odometer(p);
    _reported[p.memberId] = p;
    _remember(p);
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
    final live = channel?.isLive ?? false;
    final now = DateTime.now();
    _evaluateWatch();
    if (live || _cloudReachable) {
      unawaited(_refreshRoad());
      unawaited(_refreshWeather());
      unawaited(_refreshTolls());
    }
    if (live) {
      _offlineSince = null;
      if (_toRelay.isNotEmpty) unawaited(_relayPositions());
    } else {
      _offlineSince ??= now;
      // Realtime has been down a while: fall back to light HTTP polling,
      // which survives links too poor to hold a websocket.
      if (now.difference(_offlineSince!) > const Duration(seconds: 15) &&
          now.difference(_lastPoll) > const Duration(seconds: 15)) {
        unawaited(_poll());
      }
    }
    _updateLink();
    // Re-render so predicted vehicles keep moving between reports.
    notifyListeners();
  }

  void _updateLink() {
    final now = DateTime.now();
    final LinkMode next;
    if (channel?.isLive ?? false) {
      next = LinkMode.cloud;
    } else if (_lastPollOk != null && now.difference(_lastPollOk!) < const Duration(seconds: 60)) {
      next = LinkMode.weak;
    } else if ((meshPeersOn?.call('lora') ?? 0) > 0) {
      next = LinkMode.radio;
    } else if ((meshPeersOn?.call('nearby') ?? 0) > 0) {
      next = LinkMode.nearby;
    } else {
      next = LinkMode.isolated;
    }
    if (next != link) {
      link = next;
      notifyListeners();
    }
  }

  bool get _cloudReachable =>
      (channel?.isLive ?? false) ||
      (_lastPollOk != null && DateTime.now().difference(_lastPollOk!) < const Duration(seconds: 60));

  /// Weak-signal mode: a handful of small requests every 15 s.
  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    _lastPoll = DateTime.now();
    const t = Duration(seconds: 10);
    try {
      final mine = me == null ? null : _reported[me!.id];
      if (mine != null) await _repo.saveLastKnown(tripId, mine).timeout(t);
      await _relayPositions();

      for (final p in await _repo.lastKnownPositions(tripId).timeout(t)) {
        if (p.memberId != me?.id) _acceptPosition(p);
      }

      final since = messages.where((m) => !m.pending).lastOrNull?.createdAt;
      var q = _db.from('messages').select('*, profiles:sender_id(display_name)').eq('trip_id', tripId);
      if (since != null) q = q.gt('created_at', since.toUtc().toIso8601String());
      for (final r in await q.order('created_at').limit(50).timeout(t)) {
        _acceptMessage(ChatMessage.fromRow(r));
      }

      var wq = _db.from('waypoints').select().eq('trip_id', tripId);
      if (_waypointCursor != null) wq = wq.gt('updated_at', _waypointCursor!);
      for (final r in await wq.order('updated_at').limit(200).timeout(t)) {
        itinerary.merge(Waypoint.fromRow(r));
        _waypointCursor = r['updated_at'] as String?;
      }

      await _loadEvents().timeout(t);
      _lastPollOk = DateTime.now();
      await _flushOutbox();
    } catch (_) {
      // Still no usable connection.
    } finally {
      _polling = false;
      _updateLink();
      notifyListeners();
    }
  }

  /// Gateway: hand positions heard off-grid to the server so every car with
  /// signal (and anyone opening the trip later) sees them.
  Future<void> _relayPositions() async {
    if (_toRelay.isEmpty) return;
    final batch = _toRelay.values.toList();
    _toRelay.clear();
    try {
      await _repo.relayPositions(tripId, batch);
    } catch (_) {
      for (final p in batch) {
        _toRelay.putIfAbsent(p.memberId, () => p);
      }
    }
  }

  Future<void> _flushOutbox() async {
    final sent = await _outbox?.flush() ?? 0;
    pendingWrites = _outbox?.length ?? 0;
    if (sent > 0) notifyListeners();
  }

  Future<void> _onConnectivity() async {
    _updateLink();
    if (_cloudReachable) {
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
    int? day,
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
          day: day,
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
      await sendMessage('${mins >= 0 ? 'Running $mins min late' : 'Running ${-mins} min early'}. Schedule updated.',
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
    unawaited(_alertCtrl.close());
    crashAlarm.dispose();
    unawaited(_saveSnapshot());
    for (final d in _disposers) {
      unawaited(d());
    }
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
