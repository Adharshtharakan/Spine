import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/core/theme/spine_colors.dart';
import 'package:spine/data/repository/asset_book_repository.dart';

/// Guards the shipped catalogue. It's a hand-edited JSON file that grows every
/// time a book is added, so the invariants the app relies on are checked here
/// rather than discovered on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const manifestPath = 'assets/content/books.json';

  test('the catalogue parses and every book is well formed', () async {
    final books = await AssetBookRepository(manifestPath: manifestPath).loadBooks();

    expect(books, isNotEmpty);

    for (final book in books) {
      expect(book.id, isNotEmpty, reason: '${book.title} needs an id');
      expect(book.title, isNotEmpty);
      expect(book.author, isNotEmpty, reason: '${book.title} needs an author');
      expect(book.genre, isNotEmpty, reason: '${book.title} needs a genre');
      expect(
        book.durationLabel,
        isNotEmpty,
        reason: '${book.title} needs a duration label',
      );

      // Five ideas per book is the product, not a coincidence — the ribbon is
      // drawn from it.
      expect(
        book.ideaCount,
        5,
        reason: '${book.title} has ${book.ideaCount} ideas, expected 5',
      );

      for (final idea in book.ideas) {
        expect(idea.id, isNotEmpty);
        expect(idea.title, isNotEmpty, reason: '${book.title}: untitled idea');
        expect(idea.body, isNotEmpty, reason: '${book.title}/${idea.title}');
        expect(
          idea.duration,
          greaterThan(Duration.zero),
          reason: '${book.title}/${idea.title} has no duration',
        );
      }
    }
  });

  test('every book carries a publication date', () async {
    final books = await AssetBookRepository(manifestPath: manifestPath).loadBooks();

    for (final book in books) {
      expect(
        book.publishedAt,
        isNotNull,
        reason: '${book.title} has no "published" date, so it can never be '
            'scheduled and will sort last on the shelf',
      );
    }
  });

  test('the shipped catalogue is fully released', () async {
    final books = await AssetBookRepository(manifestPath: manifestPath).loadBooks();
    final unreleased = [
      for (final book in books)
        if (!book.isPublished(DateTime.now())) book.title,
    ];

    // Not a rule about the product — future-dated books are the point of the
    // schedule. This guards the current catalogue, where hiding a book that
    // shipped in an earlier build would look like data loss to a reader.
    expect(unreleased, isEmpty, reason: 'scheduled for the future: $unreleased');
  });

  test('ids are unique across the catalogue', () async {
    final books = await AssetBookRepository(manifestPath: manifestPath).loadBooks();

    final bookIds = books.map((book) => book.id).toList();
    expect(bookIds.toSet(), hasLength(bookIds.length), reason: 'duplicate book id');

    final ideaIds = [
      for (final book in books)
        for (final idea in book.ideas) idea.id,
    ];
    expect(ideaIds.toSet(), hasLength(ideaIds.length), reason: 'duplicate idea id');
  });

  test('every spine colour resolves to a real colour', () async {
    final raw = json.decode(await rootBundle.loadString(manifestPath));
    final entries = (raw as Map<String, dynamic>)['books'] as List<dynamic>;

    for (final entry in entries.cast<Map<String, dynamic>>()) {
      final spine = entry['spine'] as String?;
      expect(spine, isNotNull, reason: '${entry['id']} has no spine colour');

      final named = SpineColors.spinePalette.containsKey(spine!.toLowerCase());
      final hex = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(spine);
      expect(
        named || hex,
        isTrue,
        reason: '${entry['id']}: "$spine" is neither a palette name nor a hex colour',
      );
    }
  });

  test('every referenced audio asset is actually bundled', () async {
    final raw = json.decode(await rootBundle.loadString(manifestPath));
    final entries = (raw as Map<String, dynamic>)['books'] as List<dynamic>;

    for (final entry in entries.cast<Map<String, dynamic>>()) {
      for (final idea in (entry['ideas'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final ref = idea['audio'] as String?;
        if (ref == null || !ref.startsWith('asset:')) continue;

        final path = ref.substring('asset:'.length);
        // Throws — and fails the test — if the file isn't in the bundle.
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, greaterThan(0), reason: '$path is empty');
      }
    }
  });

  test('no two neighbouring cards share a spine colour', () async {
    final books = await AssetBookRepository(manifestPath: manifestPath).loadBooks();

    // Consecutive cards in the same colour make the feed look stuck when you
    // swipe, so ordering the catalogue is part of editing it.
    for (var i = 1; i < books.length; i++) {
      expect(
        books[i].spineColor,
        isNot(books[i - 1].spineColor),
        reason: '${books[i - 1].title} and ${books[i].title} share a spine colour',
      );
    }
  });
}
