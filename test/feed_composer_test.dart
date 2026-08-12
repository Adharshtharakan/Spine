import 'package:flutter_test/flutter_test.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/data/models/feed_item.dart';
import 'package:spine/services/ads/feed_composer.dart';

import 'support/fakes.dart';

/// Compact shape of a composed feed: 'B' for a book, 'A' for an ad.
String shapeOf(List<FeedItem> items) =>
    items.map((item) => item is AdFeedItem ? 'A' : 'B').join();

void main() {
  final books = [
    for (var i = 0; i < 12; i++) testBook(id: 'book-$i', title: 'Book $i'),
  ];

  test('inserts an ad on the configured cadence', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(frequency: 3, leadIn: 3),
    );

    expect(shapeOf(feed), 'BBBABBBABBBABBB');
  });

  test('frequency is configurable without touching the feed', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(frequency: 5, leadIn: 5),
    );

    expect(shapeOf(feed), 'BBBBBABBBBBABB');
  });

  test('lead-in delays the first ad', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(frequency: 2, leadIn: 6),
    );

    expect(shapeOf(feed).indexOf('A'), 6);
  });

  test('disabling ads produces a feed of pure books', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(enabled: false, frequency: 2, leadIn: 2),
    );

    expect(shapeOf(feed), 'B' * books.length);
  });

  test('respects a per-session cap', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(frequency: 2, leadIn: 2, maxAdsPerSession: 2),
    );

    expect(feed.whereType<AdFeedItem>().length, 2);
  });

  test('never ends the feed on an ad', () {
    final feed = FeedComposer.compose(
      books: books.take(4).toList(),
      config: const AdConfig(frequency: 2, leadIn: 2),
    );

    expect(feed.last, isA<BookFeedItem>());
  });

  test('ad slots are numbered in order', () {
    final feed = FeedComposer.compose(
      books: books,
      config: const AdConfig(frequency: 3, leadIn: 3),
    );

    expect(
      feed.whereType<AdFeedItem>().map((ad) => ad.position),
      [1, 2, 3],
    );
  });

  test('an empty catalogue composes an empty feed', () {
    expect(FeedComposer.compose(books: const [], config: const AdConfig()), isEmpty);
  });
}
