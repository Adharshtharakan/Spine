import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/book_progress.dart';
import 'package:spine/data/models/reading_mode.dart';
import 'package:spine/data/models/session_state.dart';
import 'package:spine/services/persistence/progress_store.dart';
import 'package:spine/state/progress_controller.dart';

void main() {
  group('BookProgress', () {
    test('survives a round trip through JSON', () {
      const original = BookProgress(
        bookId: 'atomic-habits',
        ideaIndex: 3,
        mode: ReadingMode.listen,
        saved: true,
        notifyOnWatch: true,
        resumeAt: Duration(seconds: 7),
        completedIdeas: {0, 1, 2},
      );

      final restored = BookProgress.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.resumeAt, const Duration(seconds: 7));
    });
  });

  group('streak', () {
    test('extends on consecutive days', () {
      final today = DateTime(2026, 8, 12);
      final yesterday = SessionState(
        streak: 3,
        lastActiveDay: SessionState.dayKey(today.subtract(const Duration(days: 1))),
      );

      expect(yesterday.touch(today).streak, 4);
    });

    test('holds steady within the same day', () {
      final today = DateTime(2026, 8, 12);
      final earlier = SessionState(
        streak: 3,
        lastActiveDay: SessionState.dayKey(today),
      );

      expect(earlier.touch(today).streak, 3);
    });

    test('restarts after a missed day', () {
      final today = DateTime(2026, 8, 12);
      final stale = SessionState(
        streak: 9,
        lastActiveDay: SessionState.dayKey(today.subtract(const Duration(days: 4))),
      );

      expect(stale.touch(today).streak, 1);
    });
  });

  group('ProgressController', () {
    test('persists reader state and reloads it', () async {
      final store = InMemoryProgressStore();
      final controller = ProgressController(store);
      await controller.load();

      controller.setIdeaIndex('sapiens', 2);
      controller.toggleSaved('sapiens');
      controller.setMode('sapiens', ReadingMode.listen);
      controller.setNotifyOnWatch('sapiens', true);
      controller.markIdeaComplete('sapiens', 0);
      await controller.flush();

      final reloaded = ProgressController(store);
      await reloaded.load();
      final restored = reloaded.of('sapiens');

      expect(restored.ideaIndex, 2);
      expect(restored.saved, isTrue);
      expect(restored.mode, ReadingMode.listen);
      expect(restored.notifyOnWatch, isTrue);
      expect(restored.completedIdeas, {0});
      expect(reloaded.savedBookIds, ['sapiens']);
    });

    test('remembers which book the reader was on', () async {
      final store = InMemoryProgressStore();
      final controller = ProgressController(store);
      await controller.load();

      controller.setLastBookId('deep-work');
      await controller.flush();

      final reloaded = ProgressController(store);
      await reloaded.load();

      // Stored by id, not by feed position — the shelf reorders between
      // sessions.
      expect(reloaded.lastBookId, 'deep-work');
    });

    test('an untouched book reads as a fresh start', () {
      final controller = ProgressController(InMemoryProgressStore());
      final fresh = controller.of('unknown');

      expect(fresh.ideaIndex, 0);
      expect(fresh.isStarted, isFalse);
      expect(fresh.mode, ReadingMode.read);
    });
  });
}
