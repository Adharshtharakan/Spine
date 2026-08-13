import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/review_item.dart';

/// Persistence for the review queue.
///
/// The whole queue is one record. At Spine's scale — a few hundred ideas at
/// most, written only when an idea is finished or reviewed — a single JSON blob
/// is cheaper and simpler than a database, and the interface leaves room to
/// swap in sqflite if the catalogue ever makes that false.
abstract interface class ReviewStore {
  Future<List<ReviewItem>> loadAll();

  Future<void> saveAll(List<ReviewItem> items);
}

class InMemoryReviewStore implements ReviewStore {
  List<ReviewItem> _items = const [];

  @override
  Future<List<ReviewItem>> loadAll() async => List.of(_items);

  @override
  Future<void> saveAll(List<ReviewItem> items) async => _items = List.of(items);
}

class SharedPreferencesReviewStore implements ReviewStore {
  SharedPreferencesReviewStore(this._prefs);

  static const _key = 'spine.reviews';

  final SharedPreferences _prefs;

  static Future<ReviewStore> open() async {
    try {
      return SharedPreferencesReviewStore(await SharedPreferences.getInstance());
    } catch (error) {
      debugPrint('Spine: review storage unavailable — $error');
      return InMemoryReviewStore();
    }
  }

  @override
  Future<List<ReviewItem>> loadAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return [
        for (final entry in decoded)
          ReviewItem.fromJson(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      // A queue written by another build is dropped rather than crashing the
      // launch; the ideas themselves are not lost, only their schedule.
      await _prefs.remove(_key);
      return const [];
    }
  }

  @override
  Future<void> saveAll(List<ReviewItem> items) {
    return _prefs.setString(
      _key,
      json.encode([for (final item in items) item.toJson()]),
    );
  }
}
