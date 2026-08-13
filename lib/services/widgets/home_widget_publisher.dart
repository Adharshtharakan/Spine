import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/models/book.dart';
import '../feed/daily_pick.dart';

/// Publishes today's idea to the home-screen widget.
///
/// The widget is a reader, not a client: Spine writes three strings into shared
/// storage on launch and the native widget renders them. No background work, no
/// network, nothing to keep alive.
abstract interface class HomeWidgetPublisher {
  Future<void> publish({required List<Book> books, required DateTime now});
}

class SpineHomeWidgetPublisher implements HomeWidgetPublisher {
  const SpineHomeWidgetPublisher();

  /// Must match the App Group in the iOS extension and the provider name in the
  /// Android manifest.
  static const appGroupId = 'group.com.spineapp.spine';
  static const androidProvider = 'SpineWidgetProvider';
  static const iOSWidgetName = 'SpineWidget';

  @override
  Future<void> publish({required List<Book> books, required DateTime now}) async {
    final pick = DailyPicker.pick(books: books, now: now);
    if (pick == null) return;

    final idea = pick.book.ideaAt(pick.ideaIndex);

    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await Future.wait([
        HomeWidget.saveWidgetData<String>('idea_title', idea.title),
        HomeWidget.saveWidgetData<String>('idea_body', idea.body),
        HomeWidget.saveWidgetData<String>('idea_source', pick.book.title),
        HomeWidget.saveWidgetData<String>('idea_day', pick.day),
      ]);

      await HomeWidget.updateWidget(
        androidName: androidProvider,
        iOSName: iOSWidgetName,
      );
    } catch (error) {
      // A missing widget, an unconfigured App Group, or a platform without
      // widgets at all: none of that should disturb the app.
      debugPrint('Spine: home widget update skipped — $error');
    }
  }
}

class NoopHomeWidgetPublisher implements HomeWidgetPublisher {
  final List<String> published = [];

  @override
  Future<void> publish({
    required List<Book> books,
    required DateTime now,
  }) async {
    final pick = DailyPicker.pick(books: books, now: now);
    if (pick != null) published.add(pick.book.ideaAt(pick.ideaIndex).title);
  }
}
