import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/book_progress.dart';
import '../../data/models/session_state.dart';
import 'progress_store.dart';

/// SharedPreferences-backed persistence.
///
/// One key per book keeps writes small — saving a scrub position doesn't
/// rewrite the whole library — and makes a later migration to a real database
/// a straight per-record copy.
class SharedPreferencesProgressStore implements ProgressStore {
  SharedPreferencesProgressStore(this._prefs);

  static const _prefix = 'spine.progress.';
  static const _sessionKey = 'spine.session';

  final SharedPreferences _prefs;

  /// Opens the real store, degrading to memory-only if the platform channel is
  /// unavailable — storage trouble must never stop the app from opening.
  static Future<ProgressStore> open() async {
    try {
      return SharedPreferencesProgressStore(
        await SharedPreferences.getInstance(),
      );
    } catch (error, stack) {
      debugPrint('Spine: falling back to in-memory storage — $error');
      debugPrintStack(stackTrace: stack);
      return InMemoryProgressStore();
    }
  }

  @override
  Future<Map<String, BookProgress>> loadAll() async {
    final result = <String, BookProgress>{};

    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      try {
        final progress = BookProgress.fromJson(
          json.decode(raw) as Map<String, dynamic>,
        );
        result[progress.bookId] = progress;
      } catch (_) {
        // A record written by an older build is dropped rather than crashing
        // the launch.
        await _prefs.remove(key);
      }
    }

    return result;
  }

  @override
  Future<void> save(BookProgress progress) {
    return _prefs.setString(
      '$_prefix${progress.bookId}',
      json.encode(progress.toJson()),
    );
  }

  @override
  Future<SessionState> loadSession() async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return const SessionState();
    try {
      return SessionState.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SessionState();
    }
  }

  @override
  Future<void> saveSession(SessionState session) =>
      _prefs.setString(_sessionKey, json.encode(session.toJson()));
}
