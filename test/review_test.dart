import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/review_item.dart';
import 'package:spine/services/persistence/review_store.dart';
import 'package:spine/state/review_controller.dart';

void main() {
  group('review schedule', () {
    test('expands with each pass, then retires', () {
      final from = DateTime(2026, 8, 12);

      expect(ReviewSchedule.nextDue(0, from), DateTime(2026, 8, 14));
      expect(ReviewSchedule.nextDue(1, from), DateTime(2026, 8, 18));
      expect(ReviewSchedule.nextDue(2, from), DateTime(2026, 8, 26));

      // Past the last interval an idea is considered learned.
      expect(ReviewSchedule.isRetired(ReviewSchedule.intervals.length), isTrue);
      expect(ReviewSchedule.nextDue(ReviewSchedule.intervals.length, from), isNull);
    });
  });

  group('ReviewController', () {
    late DateTime now;
    late ReviewController controller;
    late InMemoryReviewStore store;

    setUp(() async {
      now = DateTime(2026, 8, 12, 9);
      store = InMemoryReviewStore();
      controller = ReviewController(store, clock: () => now);
      await controller.load();
    });

    test('a finished idea is queued, but not due yet', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');

      expect(controller.isQueued('a-1'), isTrue);
      expect(controller.due(), isEmpty);
    });

    test('it becomes due once the interval has passed', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');

      now = now.add(const Duration(days: 2));
      expect(controller.due().map((i) => i.ideaId), ['a-1']);
    });

    test('reviewing pushes it out to the next interval', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');
      now = now.add(const Duration(days: 2));

      controller.markReviewed('a-1');

      expect(controller.due(), isEmpty);
      now = now.add(const Duration(days: 6));
      expect(controller.due().map((i) => i.ideaId), ['a-1']);
    });

    test('an idea retires after the last interval', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');

      for (var pass = 0; pass < ReviewSchedule.intervals.length; pass++) {
        now = now.add(const Duration(days: 365));
        expect(controller.due(), isNotEmpty, reason: 'pass $pass');
        controller.markReviewed('a-1');
      }

      expect(controller.isQueued('a-1'), isFalse);
      expect(controller.due(), isEmpty);
    });

    test('re-finishing an idea does not reset its schedule', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');
      now = now.add(const Duration(days: 2));
      controller.markReviewed('a-1');

      // Rereading is not recalling: the queue should ignore it.
      controller.schedule(ideaId: 'a-1', bookId: 'a');

      expect(controller.due(), isEmpty);
    });

    test('due ideas come back soonest first, and are limited', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');
      now = now.add(const Duration(days: 1));
      controller.schedule(ideaId: 'b-1', bookId: 'b');
      now = now.add(const Duration(days: 1));
      controller.schedule(ideaId: 'c-1', bookId: 'c');

      now = now.add(const Duration(days: 10));

      expect(controller.due(limit: 2).map((i) => i.ideaId), ['a-1', 'b-1']);
    });

    test('the queue survives a restart', () async {
      controller.schedule(ideaId: 'a-1', bookId: 'a');
      await Future<void>.delayed(Duration.zero);

      final reloaded = ReviewController(store, clock: () => now);
      await reloaded.load();

      expect(reloaded.isQueued('a-1'), isTrue);
      expect(reloaded.queuedCount, 1);
    });

    test('forgetting an idea drops it', () {
      controller.schedule(ideaId: 'a-1', bookId: 'a');
      controller.forget('a-1');

      expect(controller.isQueued('a-1'), isFalse);
    });
  });
}
