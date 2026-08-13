import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/book.dart';
import '../feed/daily_pick.dart';

/// The daily notification.
///
/// It carries the idea itself — title and opening line, readable from the lock
/// screen — rather than asking the reader to come back. If they read it and
/// don't open the app, that is a success, not a lost session.
///
/// Because the day's pick is a pure function of the date, the next fortnight
/// can be scheduled locally on the device. No server, no push certificates, no
/// tracking.
abstract interface class IdeaNotifier {
  /// Asks the OS for permission. Returns false if the reader declines.
  Future<bool> requestPermission();

  /// Replaces any pending notifications with the next [days] days of ideas at
  /// [timeOfDay], on the device's clock.
  Future<void> schedule({
    required List<Book> books,
    required Duration timeOfDay,
    int days,
  });

  Future<void> cancelAll();
}

class LocalIdeaNotifier implements IdeaNotifier {
  LocalIdeaNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'spine_daily_idea';
  static const _channelName = 'The day\'s idea';
  static const _channelDescription =
      'One idea from your library each morning.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;

    tz_data.initializeTimeZones();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested explicitly later, when the reader asks for
        // the notification — not thrown at them on first launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: false) ?? false;
      }
    } catch (error) {
      debugPrint('Spine: notification permission failed — $error');
    }

    return false;
  }

  @override
  Future<void> schedule({
    required List<Book> books,
    required Duration timeOfDay,
    int days = 14,
  }) async {
    await _init();
    await cancelAll();

    if (books.isEmpty) return;

    final now = tz.TZDateTime.now(tz.local);

    for (var offset = 0; offset < days; offset++) {
      var when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + offset,
        timeOfDay.inHours,
        timeOfDay.inMinutes % 60,
      );

      // Today's slot may already have passed; that day simply gets skipped
      // rather than firing immediately.
      if (!when.isAfter(now)) continue;

      final pick = DailyPicker.pick(books: books, now: when);
      if (pick == null) continue;

      final idea = pick.book.ideaAt(pick.ideaIndex);

      try {
        await _plugin.zonedSchedule(
          offset,
          idea.title,
          _preview(idea.body),
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              styleInformation: BigTextStyleInformation(''),
            ),
            iOS: DarwinNotificationDetails(presentSound: false),
          ),
          // Inexact on purpose: an idea does not need to arrive on the second,
          // and exact alarms require a permission Android 13+ makes users grant
          // by hand.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (error) {
        debugPrint('Spine: could not schedule $when — $error');
      }
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }

  /// The opening of the idea, cut at a sentence so the lock screen shows a
  /// whole thought rather than a truncated one.
  static String _preview(String body, {int limit = 140}) {
    if (body.length <= limit) return body;

    final window = body.substring(0, limit);
    final lastStop = window.lastIndexOf('. ');
    if (lastStop > 60) return window.substring(0, lastStop + 1);

    final lastSpace = window.lastIndexOf(' ');
    return '${window.substring(0, lastSpace > 0 ? lastSpace : limit)}…';
  }
}

/// Used in tests and on platforms without notification support.
class NoopIdeaNotifier implements IdeaNotifier {
  final List<String> calls = [];

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return true;
  }

  @override
  Future<void> schedule({
    required List<Book> books,
    required Duration timeOfDay,
    int days = 14,
  }) async {
    calls.add('schedule:${timeOfDay.inHours}:$days');
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');
}
