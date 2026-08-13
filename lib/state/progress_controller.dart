import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/book_progress.dart';
import '../data/models/reading_mode.dart';
import '../data/models/session_state.dart';
import '../services/persistence/progress_store.dart';

/// Per-book reader state: where you are, what mode you're in, what you saved.
///
/// Writes are debounced so a moving playhead doesn't hammer storage, and
/// flushed on pause, on app background, and on dispose.
class ProgressController extends ChangeNotifier {
  ProgressController(this._store);

  static const _flushDelay = Duration(milliseconds: 600);

  final ProgressStore _store;
  final Map<String, BookProgress> _entries = {};
  final Set<String> _dirty = {};

  Timer? _flushTimer;
  SessionState _session = const SessionState();
  bool _loaded = false;

  /// Notified the first time an idea is finished, so the review queue can pick
  /// it up without progress having to know what a review is.
  void Function(String bookId, String ideaId)? onIdeaCompleted;

  bool get isLoaded => _loaded;
  String? get lastBookId => _session.lastBookId;
  int get streak => _session.streak;
  int? get dailyIdeaHour => _session.dailyIdeaHour;

  /// Books the reader has saved. Order follows the store, which is enough for
  /// a shelf of this size.
  Iterable<String> get savedBookIds =>
      _entries.values.where((p) => p.saved).map((p) => p.bookId);

  Future<void> load({DateTime? now}) async {
    _entries.addAll(await _store.loadAll());
    _session = (await _store.loadSession()).touch(now ?? DateTime.now());
    unawaited(_store.saveSession(_session));
    _loaded = true;
    notifyListeners();
  }

  BookProgress of(String bookId) =>
      _entries[bookId] ?? BookProgress(bookId: bookId);

  bool isSaved(String bookId) => of(bookId).saved;

  // ---- Mutations -----------------------------------------------------------

  void setIdeaIndex(String bookId, int index, {bool resetResume = true}) {
    final current = of(bookId);
    if (current.ideaIndex == index && !resetResume) return;
    _write(
      current.copyWith(
        ideaIndex: index,
        resumeAt: resetResume ? Duration.zero : null,
      ),
    );
  }

  void setMode(String bookId, ReadingMode mode) {
    final current = of(bookId);
    if (current.mode == mode) return;
    _write(current.copyWith(mode: mode));
  }

  bool toggleSaved(String bookId) {
    final next = !of(bookId).saved;
    _write(of(bookId).copyWith(saved: next));
    return next;
  }

  void setNotifyOnWatch(String bookId, bool value) {
    if (of(bookId).notifyOnWatch == value) return;
    _write(of(bookId).copyWith(notifyOnWatch: value));
  }

  /// Called continuously while listening; persisted lazily.
  void setResumePosition(String bookId, int ideaIndex, Duration position) {
    final current = of(bookId);
    if (current.ideaIndex != ideaIndex) return;
    if ((current.resumeAt - position).abs() < const Duration(seconds: 1)) {
      // Keep the in-memory value fresh without scheduling a write for every
      // playhead tick.
      _entries[bookId] = current.copyWith(resumeAt: position);
      return;
    }
    _write(current.copyWith(resumeAt: position), notify: false);
  }

  void markIdeaComplete(String bookId, int ideaIndex, {String? ideaId}) {
    final current = of(bookId);
    if (current.completedIdeas.contains(ideaIndex)) return;
    _write(
      current.copyWith(completedIdeas: {...current.completedIdeas, ideaIndex}),
    );
    if (ideaId != null) onIdeaCompleted?.call(bookId, ideaId);
  }

  bool toggleSavedIdea(String bookId, String ideaId) {
    final current = of(bookId);
    final next = {...current.savedIdeaIds};
    final added = next.add(ideaId);
    if (!added) next.remove(ideaId);

    _write(current.copyWith(savedIdeaIds: next));
    return added;
  }

  /// Every saved idea across the library, as (bookId, ideaId) pairs.
  Iterable<(String, String)> get savedIdeas => [
    for (final entry in _entries.values)
      for (final ideaId in entry.savedIdeaIds) (entry.bookId, ideaId),
  ];

  /// null turns the daily idea off.
  void setDailyIdeaHour(int? hour) {
    if (_session.dailyIdeaHour == hour) return;
    _session = _session.copyWith(
      dailyIdeaHour: hour,
      clearDailyIdeaHour: hour == null,
    );
    unawaited(_store.saveSession(_session));
    notifyListeners();
  }

  void setLastBookId(String bookId) {
    if (_session.lastBookId == bookId) return;
    _session = _session.copyWith(lastBookId: bookId);
    unawaited(_store.saveSession(_session));
  }

  /// Total ideas finished across the library — the one number the profile shows.
  int get ideasCompleted =>
      _entries.values.fold(0, (sum, p) => sum + p.completedIdeas.length);

  int get booksStarted => _entries.values.where((p) => p.isStarted).length;

  Future<void> flush() async {
    _flushTimer?.cancel();
    final pending = _dirty.toList();
    _dirty.clear();
    for (final id in pending) {
      final entry = _entries[id];
      if (entry != null) await _store.save(entry);
    }
  }

  void _write(BookProgress next, {bool notify = true}) {
    _entries[next.bookId] = next;
    _dirty.add(next.bookId);
    _scheduleFlush();
    if (notify) notifyListeners();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () => unawaited(flush()));
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    unawaited(flush());
    super.dispose();
  }
}
