import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../edge/edge_client.dart';

/// Push notifications (Firebase Cloud Messaging) and on-device alerts.
///
/// Pushes reach people who don't have the trip open: an SOS, a hazard, a
/// join request, a regroup point. Firebase is optional; without its keys in
/// env.json the app works and only on-device notifications are shown.
abstract final class PushService {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static bool _firebaseReady = false;
  static StreamSubscription<String>? _refresh;
  static String? _startedFor;

  /// Called when a notification for a trip is tapped.
  static void Function(String tripId)? onOpenTrip;

  static const _sos = AndroidNotificationChannel('sos', 'SOS and emergencies',
      description: 'A member of your convoy needs help.', importance: Importance.max);
  static const _convoy = AndroidNotificationChannel('convoy', 'Convoy updates',
      description: 'Hazards, regroup points, plan changes and join requests.', importance: Importance.high);

  static Future<void> _initLocal() async {
    if (_localReady) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final trip = r.payload;
        if (trip != null && trip.isNotEmpty) onOpenTrip?.call(trip);
      },
    );
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_sos);
    await android?.createNotificationChannel(_convoy);
    _localReady = true;
  }

  /// Sets up notifications for the signed-in user. Safe to call repeatedly.
  static Future<void> start(SupabaseClient db) async {
    try {
      await _initLocal();
    } catch (_) {
      // Notifications unavailable (tests, desktop): alerts still show in-app.
    }
    final uid = db.auth.currentUser?.id;
    if (!Env.hasFirebase || uid == null || uid == _startedFor) return;
    _startedFor = uid;
    try {
      if (!_firebaseReady) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: Env.firebaseApiKey,
            appId: Env.firebaseAppId,
            messagingSenderId: Env.firebaseSenderId,
            projectId: Env.firebaseProjectId,
          ),
        );
        _firebaseReady = true;
        FirebaseMessaging.onMessage.listen((m) {
          final n = m.notification;
          if (n == null) return;
          unawaited(show(m.data['kind'] == 'sos' ? 'sos' : 'convoy', n.title ?? 'DriveSync', n.body ?? '',
              tripId: m.data['trip_id'] as String?));
        });
        FirebaseMessaging.onMessageOpenedApp.listen((m) {
          final trip = m.data['trip_id'] as String?;
          if (trip != null) onOpenTrip?.call(trip);
        });
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        final trip = initial?.data['trip_id'] as String?;
        if (trip != null) scheduleMicrotask(() => onOpenTrip?.call(trip));
      }
      final fm = FirebaseMessaging.instance;
      // The Worker sends with FCM HTTP v1 `message.token`, which takes the
      // registration token (not the installation id the newer API returns).
      await fm.requestPermission(alert: true, sound: true, badge: true, criticalAlert: false);
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token != null) await _register(db, token);
      await _refresh?.cancel();
      // ignore: deprecated_member_use
      _refresh = fm.onTokenRefresh.listen((t) => _register(db, t));
    } catch (_) {
      // Misconfigured or no Play services: carry on without pushes.
    }
  }

  static Future<void> _register(SupabaseClient db, String token) async {
    try {
      await db.rpc('register_device_token', params: {'p_token': token, 'p_platform': Platform.isIOS ? 'ios' : 'android'});
    } catch (_) {}
  }

  /// Forgets this phone's token (on sign-out) so pushes stop.
  static Future<void> stop(SupabaseClient db) async {
    _startedFor = null;
    if (!_firebaseReady) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await db.from('device_tokens').delete().eq('token', token);
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  /// Asks the Worker to push to the rest of the party. Best effort: the
  /// event itself already travels over Realtime and the radio.
  static Future<void> notifyParty(SupabaseClient db,
      {required String tripId, required String kind, required String title, required String body, List<String>? to}) async {
    try {
      await EdgeClient(db).post('/notify', {'trip_id': tripId, 'kind': kind, 'title': title, 'body': body, 'to': ?to});
    } catch (_) {}
  }

  /// A notification on this phone (an SOS heard over the radio while the
  /// app is in the background, say).
  static Future<void> show(String channel, String title, String body, {String? tripId}) async {
    try {
      await _initLocal();
      final sos = channel == 'sos';
      await _local.show(
        id: title.hashCode ^ body.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            sos ? _sos.id : _convoy.id,
            sos ? _sos.name : _convoy.name,
            importance: sos ? Importance.max : Importance.high,
            priority: sos ? Priority.max : Priority.high,
            category: sos ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.message,
            fullScreenIntent: sos,
          ),
          iOS: DarwinNotificationDetails(interruptionLevel: sos ? InterruptionLevel.timeSensitive : InterruptionLevel.active),
        ),
        payload: tripId,
      );
    } catch (_) {}
  }
}
