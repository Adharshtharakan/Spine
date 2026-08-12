import '../../core/config/ad_config.dart';
import '../../data/models/book.dart';
import '../../data/models/feed_item.dart';

/// Weaves ad cards into a list of books according to [AdConfig].
///
/// Pure and synchronous — the whole ad cadence is one testable function, and
/// the feed never learns what a frequency is:
///
///   frequency 3, leadIn 3 → B B B Ad B B B Ad …
///   enabled: false        → B B B B B …
abstract final class FeedComposer {
  static const adSlotId = 'feed_card';

  static List<FeedItem> compose({
    required List<Book> books,
    required AdConfig config,
  }) {
    if (books.isEmpty) return const [];
    if (!config.enabled) {
      return [for (final book in books) BookFeedItem(book)];
    }

    final items = <FeedItem>[];
    var adsInserted = 0;

    for (var i = 0; i < books.length; i++) {
      items.add(BookFeedItem(books[i]));

      final booksShown = i + 1;
      final pastLeadIn = booksShown >= config.leadIn;
      final onCadence = (booksShown - config.leadIn) % config.frequency == 0;
      final underCap =
          config.maxAdsPerSession == null ||
          adsInserted < config.maxAdsPerSession!;
      final isLastBook = booksShown == books.length;

      // Never end the feed on an ad — the last thing on the shelf is a book.
      if (pastLeadIn && onCadence && underCap && !isLastBook) {
        adsInserted++;
        items.add(AdFeedItem(slot: adSlotId, position: adsInserted));
      }
    }

    return List.unmodifiable(items);
  }
}
