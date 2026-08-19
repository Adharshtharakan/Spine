import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/review_item.dart';
import '../services/persistence/review_store.dart';

/// The review queue: which ideas are coming back, and when.
///
/// An idea enters the queue when it is finished, comes back on an expanding
/// schedule, and retires once it has survived the last interval. Nothing here
/// judges the reader — reviewing is acknowledging, not answering.
class ReviewController extends ChangeNotifier {
  ReviewController(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ReviewStore _store;
  final DateTime Function() _clock;

  final Map<String, ReviewItem> _items = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  int get queuedCount => _items.length;

  Future<void> load() async {
    for (final item in await _store.loadAll()) {
      _items[item.ideaId] = item;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Ideas ready to come back, soonest-due first.
  List<ReviewItem> due({int limit = 3}) {
    final now = _clock();
    final ready = [
      for (final item in _items.values)
        if (item.isDue(now)) item,
    ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

    return ready.take(limit).toList(growable: false);
  }

  bool isQueued(String ideaId) => _items.containsKey(ideaId);

  /// Called when an idea is finished. Re-finishing an idea already in the queue
  /// leaves its schedule alone — rereading isn't the same as recalling.
  void schedule({required String ideaId, required String bookId}) {
    if (_items.containsKey(ideaId)) return;

    final dueAt = ReviewSchedule.nextDue(0, _clock());
    if (dueAt == null) return;

    _items[ideaId] = ReviewItem(ideaId: ideaId, bookId: bookId, dueAt: dueAt);
    _persist();
    notifyListeners();
  }

  /// The reader has seen this one again.
  ///
  /// [remembered] is what makes this spaced repetition rather than a timer:
  /// recalling an idea pushes it out to the next interval, failing to recall it
  /// sends it back to the start so it returns in days rather than months. An
  /// idea you have just proved you forgot is the last one that should be
  /// treated as learned.
  void markReviewed(String ideaId, {bool remembered = true}) {
    final item = _items[ideaId];
    if (item == null) return;

    final nextStage = remembered ? item.stage + 1 : 0;
    final dueAt = ReviewSchedule.nextDue(nextStage, _clock());

    if (dueAt == null) {
      _items.remove(ideaId);
    } else {
      _items[ideaId] = item.copyWith(stage: nextStage, dueAt: dueAt);
    }

    _persist();
    notifyListeners();
  }

  /// Drops an idea from the queue for good — used when a reader unsaves or
  /// otherwise signals they're done with it.
  void forget(String ideaId) {
    if (_items.remove(ideaId) == null) return;
    _persist();
    notifyListeners();
  }

  void _persist() => unawaited(_store.saveAll(_items.values.toList()));
}
