import 'book.dart';
import 'idea.dart';

/// What a single full-screen page of the feed can be.
///
/// The feed renders `FeedItem`s, not books. That one indirection is what lets
/// ads (and, later, collections or editor's notes) appear between cards
/// without the scrolling architecture knowing anything about them.
sealed class FeedItem {
  const FeedItem();

  /// Stable key for the page — used for PageStorage and widget keys.
  String get key;
}

class BookFeedItem extends FeedItem {
  const BookFeedItem(this.book);

  final Book book;

  @override
  String get key => 'book:${book.id}';
}

/// The day's idea, pulled from somewhere in the library and pinned above the
/// shelf.
///
/// It borrows an idea rather than owning one: reading it changes nothing about
/// the book it came from, and the card exists to be a way in.
class DailyIdeaFeedItem extends FeedItem {
  const DailyIdeaFeedItem({
    required this.book,
    required this.ideaIndex,
    required this.day,
  });

  final Book book;
  final int ideaIndex;

  /// `yyyy-mm-dd` the pick belongs to — also what makes the key change at
  /// midnight, so the card rebuilds rather than going stale.
  final String day;

  Idea get idea => book.ideaAt(ideaIndex);

  @override
  String get key => 'today:$day';
}

class AdFeedItem extends FeedItem {
  const AdFeedItem({required this.slot, required this.position});

  /// Which ad unit this card should fill (see `AdSlot`).
  final String slot;

  /// Ordinal of this ad within the session, starting at 1. Handy for reporting
  /// and for varying creative later.
  final int position;

  @override
  String get key => 'ad:$slot:$position';
}
