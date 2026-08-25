import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/book_progress.dart';
import 'package:spine/data/models/session_state.dart';
import 'package:spine/services/reading/sentences.dart';

void main() {
  group('Sentences', () {
    test('splits prose on sentence endings', () {
      final result = Sentences.of(
        'Lasting change starts with who you become. '
        'Every small habit is a vote.',
      );

      expect(result, [
        'Lasting change starts with who you become.',
        'Every small habit is a vote.',
      ]);
    });

    test('keeps a trailing fragment that never terminates', () {
      expect(Sentences.of('No full stop here'), ['No full stop here']);
    });

    test('keeps closing punctuation with its own sentence', () {
      expect(Sentences.of('He said "stop." Then he left.'), [
        'He said "stop."',
        'Then he left.',
      ]);
    });

    test('handles questions and exclamations', () {
      expect(Sentences.of('Why? Because it works!'), [
        'Why?',
        'Because it works!',
      ]);
    });

    test('an empty body splits to nothing', () {
      expect(Sentences.of('   '), isEmpty);
    });

    test('rejoining the pieces reproduces the prose', () {
      const body = 'One thing. Then another. And a third.';
      expect(Sentences.of(body).join(' '), body);
    });
  });

  group('several kept lines share as one passage', () {
    const body = 'First thought. Second thought. Third thought.';

    test('reads in written order, not the order they were tapped', () {
      // Tapped back to front — the passage must not come out reversed.
      final passage = Sentences.passage(body, [
        'Third thought.',
        'First thought.',
      ]);

      expect(passage, 'First thought. Third thought.');
    });

    test('keeps all three when all three are kept', () {
      expect(
        Sentences.passage(body, [
          'Second thought.',
          'Third thought.',
          'First thought.',
        ]),
        body,
      );
    });

    test('a single line still shares on its own', () {
      expect(Sentences.passage(body, ['Second thought.']), 'Second thought.');
    });

    test('nothing kept shares nothing', () {
      expect(Sentences.passage(body, const []), isNull);
    });

    test('a line the idea no longer contains is dropped', () {
      // Ideas get edited; a stored highlight that no longer appears would
      // otherwise be shared out of context.
      final passage = Sentences.passage(body, [
        'First thought.',
        'A line from an older draft.',
      ]);

      expect(passage, 'First thought.');
    });

    test('every line gone leaves nothing rather than an empty string', () {
      expect(Sentences.passage(body, ['Nothing that matches.']), isNull);
    });
  });

  group('BookProgress highlights', () {
    test('survive a round trip through JSON', () {
      const progress = BookProgress(
        bookId: 'atomic-habits',
        highlights: {
          'atomic-habits-1': ['Every small habit is a vote.'],
        },
      );

      final restored = BookProgress.fromJson(progress.toJson());
      expect(restored.highlightsFor('atomic-habits-1'), [
        'Every small habit is a vote.',
      ]);
      expect(restored, progress);
    });

    test('a book with no highlights stays absent from its JSON', () {
      const progress = BookProgress(bookId: 'atomic-habits');
      expect(progress.toJson().containsKey('highlights'), isFalse);
      expect(BookProgress.fromJson(progress.toJson()).highlights, isEmpty);
    });
  });

  group('streak repair', () {
    // The dates matter more than anything else here, so they're explicit.
    final monday = DateTime(2026, 3, 2);
    final tuesday = DateTime(2026, 3, 3);
    final wednesday = DateTime(2026, 3, 4);
    final nextWeek = DateTime(2026, 3, 9);

    SessionState onDay(int streak, DateTime day) => SessionState(
      streak: streak,
      lastActiveDay: SessionState.dayKey(day),
    );

    test('missing exactly one day offers the streak back', () {
      final state = onDay(12, monday).touch(wednesday);

      expect(state.streak, 1, reason: 'the streak still breaks');
      expect(state.brokenStreak, 12);
      expect(state.canRepair(wednesday), isTrue);
    });

    test('a longer lapse is not repairable at all', () {
      final state = onDay(40, monday).touch(nextWeek);

      expect(state.streak, 1);
      expect(state.brokenStreak, 0);
      expect(state.canRepair(nextWeek), isFalse);
    });

    test('an unbroken run never offers a repair', () {
      final state = onDay(3, monday).touch(tuesday);

      expect(state.streak, 4);
      expect(state.brokenStreak, 0);
    });

    test('repairing restores the streak and counts today', () {
      final broken = onDay(12, monday).touch(wednesday);
      final repaired = broken.repair(wednesday);

      expect(repaired.streak, 13);
      expect(repaired.brokenStreak, 0);
      expect(repaired.lastActiveDay, SessionState.dayKey(wednesday));
    });

    test('only one repair per calendar month', () {
      final repaired = onDay(12, monday).touch(wednesday).repair(wednesday);

      // A second lapse in the same month.
      final brokenAgain = repaired
          .copyWith(
            streak: 6,
            lastActiveDay: SessionState.dayKey(DateTime(2026, 3, 20)),
          )
          .touch(DateTime(2026, 3, 22));

      expect(brokenAgain.brokenStreak, 6, reason: 'the loss is still recorded');
      expect(
        brokenAgain.canRepair(DateTime(2026, 3, 22)),
        isFalse,
        reason: 'but March has been spent',
      );
      expect(brokenAgain.canRepair(DateTime(2026, 4, 2)), isTrue);
    });

    test('declining spends nothing', () {
      final broken = onDay(12, monday).touch(wednesday);
      final declined = broken.declineRepair();

      expect(declined.brokenStreak, 0, reason: 'the offer is gone');
      expect(
        declined.lastRepairMonth,
        isNull,
        reason: "but the month's repair was not used",
      );
    });

    test('survives a round trip through JSON', () {
      final broken = onDay(12, monday).touch(wednesday);
      final restored = SessionState.fromJson(broken.toJson());

      expect(restored.brokenStreak, 12);
      expect(restored.canRepair(wednesday), isTrue);
    });
  });

  group('appearance', () {
    test('defaults to dark, so an upgrade keeps the app people had', () {
      expect(const SessionState().darkMode, isTrue);
    });

    test('the choice survives a round trip', () {
      const chosen = SessionState(darkMode: false);
      expect(SessionState.fromJson(chosen.toJson()).darkMode, isFalse);
    });

    test('repairing a streak does not silently flip the mode', () {
      // repair() rebuilds the whole object rather than copying, so every
      // unrelated preference has to be carried across by hand.
      final broken = const SessionState(
        darkMode: false,
        streak: 9,
        lastActiveDay: '2026-03-02',
      ).touch(DateTime(2026, 3, 4));

      expect(broken.repair(DateTime(2026, 3, 4)).darkMode, isFalse);
    });
  });
}
