import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/book.dart';
import 'package:spine/data/models/book_progress.dart';
import 'package:spine/services/feed/daily_pick.dart';
import 'package:spine/services/feed/shelf_order.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 8, 12);

  Book dated(String id, DateTime published) =>
      testBook(id: id, title: id, publishedAt: published);

  List<String> idsOf(List<Book> books) => [for (final b in books) b.id];

  group('publication schedule', () {
    test('books dated in the future are not on the shelf yet', () {
      final books = [
        dated('out-today', now),
        dated('last-week', now.subtract(const Duration(days: 7))),
        dated('next-week', now.add(const Duration(days: 7))),
      ];

      final shelf = ShelfOrder.arrange(
        books: books,
        progressOf: (id) => BookProgress(bookId: id),
        now: now,
      );

      expect(idsOf(shelf), ['out-today', 'last-week']);
    });

    test('a book published earlier today counts as out', () {
      final book = dated('this-morning', DateTime(2026, 8, 12, 6));
      expect(book.isPublished(DateTime(2026, 8, 12, 9)), isTrue);
    });

    test('undated books are always on the shelf', () {
      final book = testBook(id: 'evergreen');
      expect(book.isPublished(now), isTrue);
      expect(book.isNew(now), isFalse);
    });

    test('recent books are marked new, older ones are not', () {
      expect(dated('a', now.subtract(const Duration(days: 2))).isNew(now), isTrue);
      expect(dated('b', now.subtract(const Duration(days: 30))).isNew(now), isFalse);
    });
  });

  group('shelf order', () {
    test('unread books lead with the most recent first', () {
      final books = [
        dated('older', now.subtract(const Duration(days: 20))),
        dated('newest', now.subtract(const Duration(days: 1))),
        dated('middle', now.subtract(const Duration(days: 10))),
      ];

      final shelf = ShelfOrder.arrange(
        books: books,
        progressOf: (id) => BookProgress(bookId: id),
        now: now,
      );

      expect(idsOf(shelf), ['newest', 'middle', 'older']);
    });

    test('a started book resurfaces above newer unread ones', () {
      final books = [
        dated('newest', now.subtract(const Duration(days: 1))),
        dated('started', now.subtract(const Duration(days: 40))),
      ];

      final shelf = ShelfOrder.arrange(
        books: books,
        progressOf: (id) => id == 'started'
            ? BookProgress(bookId: id, ideaIndex: 2, completedIdeas: const {0, 1})
            : BookProgress(bookId: id),
        now: now,
      );

      expect(idsOf(shelf), ['started', 'newest']);
    });

    test('finished books drop below everything else', () {
      final books = [
        dated('finished', now.subtract(const Duration(days: 1))),
        dated('unread', now.subtract(const Duration(days: 30))),
        dated('started', now.subtract(const Duration(days: 60))),
      ];

      final shelf = ShelfOrder.arrange(
        books: books,
        progressOf: (id) => switch (id) {
          'finished' => BookProgress(
            bookId: id,
            completedIdeas: const {0, 1, 2, 3, 4},
          ),
          'started' => BookProgress(bookId: id, ideaIndex: 1),
          _ => BookProgress(bookId: id),
        },
        now: now,
      );

      expect(idsOf(shelf), ['started', 'unread', 'finished']);
    });

    test('bands are classified from progress, not from position', () {
      final book = testBook(id: 'b', ideaCount: 3);

      expect(
        ShelfOrder.bandOf(book, const BookProgress(bookId: 'b')),
        ShelfBand.unread,
      );
      expect(
        ShelfOrder.bandOf(
          book,
          const BookProgress(bookId: 'b', completedIdeas: {0}),
        ),
        ShelfBand.continuing,
      );
      expect(
        ShelfOrder.bandOf(
          book,
          const BookProgress(bookId: 'b', completedIdeas: {0, 1, 2}),
        ),
        ShelfBand.finished,
      );
    });

    test('an undated catalogue keeps its file order', () {
      final books = [
        testBook(id: 'a'),
        testBook(id: 'b'),
        testBook(id: 'c'),
      ];

      final shelf = ShelfOrder.arrange(
        books: books,
        progressOf: (id) => BookProgress(bookId: id),
        now: now,
      );

      expect(idsOf(shelf), ['a', 'b', 'c']);
    });
  });

  group('daily pick', () {
    // Dated well in the past, so every sampled day has the full shelf to
    // choose from.
    final books = [
      for (var i = 0; i < 6; i++)
        dated('book-$i', now.subtract(Duration(days: 200 + i))),
    ];

    test('is the same all day', () {
      final morning = DailyPicker.pick(books: books, now: DateTime(2026, 8, 12, 7));
      final night = DailyPicker.pick(books: books, now: DateTime(2026, 8, 12, 23));

      expect(morning!.book.id, night!.book.id);
      expect(morning.ideaIndex, night.ideaIndex);
      expect(morning.day, '2026-08-12');
    });

    test('changes across a week', () {
      final picks = {
        for (var day = 1; day <= 7; day++)
          DailyPicker.pick(books: books, now: DateTime(2026, 8, day))!,
      };

      // Not a guarantee that every day differs, but a fixed pick would collapse
      // to one entry.
      expect(picks.map((p) => '${p.book.id}/${p.ideaIndex}').toSet().length,
          greaterThan(1));
    });

    test('never points outside the book', () {
      for (var day = 1; day <= 28; day++) {
        final pick = DailyPicker.pick(books: books, now: DateTime(2026, 8, day))!;
        expect(pick.ideaIndex, inInclusiveRange(0, pick.book.ideaCount - 1));
      }
    });

    test('ignores books that are not out yet', () {
      final unreleased = [dated('future', now.add(const Duration(days: 3)))];
      expect(DailyPicker.pick(books: unreleased, now: now), isNull);
    });

    test('an empty catalogue has no pick', () {
      expect(DailyPicker.pick(books: const [], now: now), isNull);
    });
  });
}
