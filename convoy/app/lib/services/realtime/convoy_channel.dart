import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/social.dart';
import '../../data/models/trip.dart';
import '../../data/models/waypoint.dart';
import '../voice/ptt_service.dart';

enum ChannelStatus { connecting, live, offline }

/// One private Realtime channel per trip (`trip:<id>`), authorised by the
/// RLS policies on `realtime.messages`, so only party members can listen or
/// send. It multiplexes:
///
/// * `pos`  — live GPS fixes (broadcast only; nothing written per fix)
/// * `rtc`  — WebRTC offers/answers/ICE for push-to-talk (addressed by member)
/// * `ptt`  — floor control: who is talking
/// * presence — who has the app open
/// * Postgres changes on `waypoints`, `messages`, `trip_members`, `trips`
class ConvoyChannel implements PttSignaller {
  ConvoyChannel(this._db, {required this.tripId, required this.memberId});

  final SupabaseClient _db;
  final String tripId;
  final String memberId;
  RealtimeChannel? _channel;

  final _positions = StreamController<VehiclePosition>.broadcast();
  final _waypoints = StreamController<Waypoint>.broadcast();
  final _messages = StreamController<ChatMessage>.broadcast();
  final _signals = StreamController<Map<String, dynamic>>.broadcast();
  final _ptt = StreamController<Map<String, dynamic>>.broadcast();
  final _members = StreamController<void>.broadcast();
  final _trip = StreamController<Trip>.broadcast();
  final _online = StreamController<Set<String>>.broadcast();
  final _status = StreamController<ChannelStatus>.broadcast();

  Stream<VehiclePosition> get positions => _positions.stream;
  Stream<Waypoint> get waypoints => _waypoints.stream;
  Stream<ChatMessage> get messages => _messages.stream;
  @override
  Stream<Map<String, dynamic>> get signals => _signals.stream;
  @override
  Stream<Map<String, dynamic>> get ptt => _ptt.stream;
  Stream<void> get membersChanged => _members.stream;
  Stream<Trip> get tripChanged => _trip.stream;
  Stream<Set<String>> get online => _online.stream;
  Stream<ChannelStatus> get status => _status.stream;

  ChannelStatus _current = ChannelStatus.connecting;
  ChannelStatus get currentStatus => _current;

  static Map<String, dynamic> _body(Map<String, dynamic> msg) =>
      msg['payload'] is Map ? Map<String, dynamic>.from(msg['payload'] as Map) : msg;

  void connect() {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'trip_id',
      value: tripId,
    );
    _channel = _db
        .channel('trip:$tripId',
            opts: RealtimeChannelConfig(private: true, key: memberId, enabled: true))
        .onBroadcast(
          event: 'pos',
          callback: (m) {
            final p = VehiclePosition.fromJson(_body(m));
            if (p.memberId != memberId) _positions.add(p);
          },
        )
        .onBroadcast(
          event: 'rtc',
          callback: (m) {
            final b = _body(m);
            if (b['to'] == memberId) _signals.add(b);
          },
        )
        .onBroadcast(event: 'ptt', callback: (m) => _ptt.add(_body(m)))
        .onPresenceSync((_) {
          final ids = <String>{
            for (final s in _channel!.presenceState()) s.key,
          };
          _online.add(ids);
        })
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'waypoints',
          filter: filter,
          callback: (c) {
            if (c.newRecord.isNotEmpty) _waypoints.add(Waypoint.fromRow(c.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (c) => _messages.add(ChatMessage.fromRow(c.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trip_members',
          filter: filter,
          callback: (_) => _members.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: tripId),
          callback: (c) => _trip.add(Trip.fromRow(c.newRecord)),
        )
        .subscribe((status, error) async {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              _setStatus(ChannelStatus.live);
              await _channel?.track({'member': memberId, 'at': DateTime.now().toUtc().toIso8601String()});
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.closed:
              _setStatus(ChannelStatus.offline);
          }
        });
  }

  void _setStatus(ChannelStatus s) {
    _current = s;
    _status.add(s);
  }

  bool get isLive => _current == ChannelStatus.live;

  Future<bool> _send(String event, Map<String, dynamic> payload) async {
    final ch = _channel;
    if (ch == null || !isLive) return false;
    try {
      final res = await ch.sendBroadcastMessage(event: event, payload: payload);
      return res == ChannelResponse.ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendPosition(VehiclePosition p) => _send('pos', p.toJson());

  @override
  Future<bool> sendSignal(String to, Map<String, dynamic> body) =>
      _send('rtc', {...body, 'from': memberId, 'to': to});

  @override
  Future<bool> sendPtt(Map<String, dynamic> body) => _send('ptt', {...body, 'from': memberId});

  Future<void> dispose() async {
    final ch = _channel;
    _channel = null;
    if (ch != null) await _db.removeChannel(ch);
    for (final c in [_positions, _waypoints, _messages, _signals, _ptt, _members, _trip, _online, _status]) {
      await c.close();
    }
  }
}
