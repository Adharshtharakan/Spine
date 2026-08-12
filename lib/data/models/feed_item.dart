import 'book.dart';

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
