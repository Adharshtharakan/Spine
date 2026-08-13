import '../../data/models/book.dart';
import '../../data/models/session_state.dart';

/// One idea, chosen for the day.
class DailyPick {
  const DailyPick({
    required this.book,
    required this.ideaIndex,
    required this.day,
  });

  final Book book;
  final int ideaIndex;
  final String day;
}

/// Chooses the idea that leads the feed today.
///
/// Deterministic from the date alone: everyone opening the app on the same day
/// gets the same idea, tomorrow's is different, and it needs no server, no
/// stored state, and no randomness that could repeat twice in one day.
abstract final class DailyPicker {
  static DailyPick? pick({required List<Book> books, required DateTime now}) {
    final eligible = [
      for (final book in books)
        if (book.isPublished(now) && book.ideaCount > 0) book,
    ];
    if (eligible.isEmpty) return null;

    final day = SessionState.dayKey(now);
    final seed = _hash(day);

    // Two independent draws off one seed: which book, then which of its ideas.
    final book = eligible[seed % eligible.length];
    final ideaIndex = (seed ~/ eligible.length) % book.ideaCount;

    return DailyPick(book: book, ideaIndex: ideaIndex, day: day);
  }

  /// FNV-1a. Small, stable across platforms and releases — which matters,
  /// because `hashCode` is not guaranteed to be either.
  static int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
