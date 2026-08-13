import '../../data/models/book.dart';
import '../../data/models/book_progress.dart';

/// How a book is being treated by the shelf ordering, in priority order.
enum ShelfBand {
  /// Started, not finished. These come back to the top so a half-read book
  /// isn't lost behind everything published since.
  continuing,

  /// Never opened. Newest first.
  unread,

  /// Every idea read. Still on the shelf, just no longer competing for the top.
  finished,
}

/// Decides what order the shelf is in.
///
/// Pure and synchronous, so the whole rule is one testable function. Call it
/// **once per session**: the ordering depends on reading progress, so
/// recomputing it while someone reads would slide the feed around under their
/// thumb.
abstract final class ShelfOrder {
  static List<Book> arrange({
    required List<Book> books,
    required BookProgress Function(String bookId) progressOf,
    required DateTime now,
  }) {
    final published = [
      for (final book in books)
        if (book.isPublished(now)) book,
    ];

    // Decorate once — bandOf and the sort key both read progress, and progress
    // lookups shouldn't be repeated inside a comparator.
    final decorated = [
      for (final book in published)
        (book: book, progress: progressOf(book.id)),
    ];

    int bandRank(ShelfBand band) => ShelfBand.values.indexOf(band);

    decorated.sort((a, b) {
      final byBand = bandRank(bandOf(a.book, a.progress))
          .compareTo(bandRank(bandOf(b.book, b.progress)));
      if (byBand != 0) return byBand;

      // Within a band, the most recently published book leads. Undated books
      // sort last so a catalogue that never sets dates keeps its file order.
      final aDate = a.book.publishedAt;
      final bDate = b.book.publishedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return List.unmodifiable([for (final entry in decorated) entry.book]);
  }

  static ShelfBand bandOf(Book book, BookProgress progress) {
    if (progress.completedIdeas.length >= book.ideaCount) {
      return ShelfBand.finished;
    }
    return progress.isStarted ? ShelfBand.continuing : ShelfBand.unread;
  }
}
