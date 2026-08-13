import 'package:flutter/foundation.dart';

import '../core/config/ad_config.dart';
import '../data/models/book.dart';
import '../data/models/book_progress.dart';
import '../data/models/feed_item.dart';
import '../data/models/review_item.dart';
import '../data/repository/book_repository.dart';
import '../services/ads/feed_composer.dart';
import '../services/feed/daily_pick.dart';
import '../services/feed/shelf_order.dart';

enum LibraryStatus { loading, ready, failed }

/// Owns the catalogue and the composed feed.
///
/// Everything downstream reads `feedItems`; nothing downstream knows whether an
/// entry is a book, the day's idea, or an ad until it renders one.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required BookRepository repository,
    required AdConfig adConfig,
    DateTime Function()? clock,
  }) : _repository = repository,
       _adConfig = adConfig,
       _clock = clock ?? DateTime.now;

  final BookRepository _repository;
  final DateTime Function() _clock;
  AdConfig _adConfig;

  LibraryStatus _status = LibraryStatus.loading;
  Object? _error;

  /// Everything in the catalogue, including books not yet published.
  List<Book> _catalogue = const [];

  /// Published books, in shelf order — fixed for the session.
  List<Book> _books = const [];

  List<FeedItem> _feedItems = const [];
  final Map<String, String> _searchIndex = {};

  LibraryStatus get status => _status;
  Object? get error => _error;
  List<Book> get books => _books;
  List<FeedItem> get feedItems => _feedItems;
  AdConfig get adConfig => _adConfig;

  /// Books written but not yet released. Only useful for diagnostics.
  int get scheduledCount => _catalogue.length - _books.length;

  /// Ideas due to come back, resolved into cards at compose time.
  List<ReviewItem> _dueReviews = const [];

  /// [progressOf] decides the ordering: books you've started come back to the
  /// top. It is read once, here — see `ShelfOrder.arrange`. [dueReviews] are the
  /// ideas the review queue wants to resurface today.
  Future<void> load({
    BookProgress Function(String bookId)? progressOf,
    List<ReviewItem> dueReviews = const [],
  }) async {
    _dueReviews = dueReviews;
    _status = LibraryStatus.loading;
    notifyListeners();

    try {
      _catalogue = await _repository.loadBooks();
      _searchIndex
        ..clear()
        ..addEntries(
          _catalogue.map((book) => MapEntry(book.id, book.buildSearchIndex())),
        );

      _arrange(progressOf ?? (id) => BookProgress(bookId: id));
      _status = LibraryStatus.ready;
      _error = null;
    } catch (error, stack) {
      _error = error;
      _status = LibraryStatus.failed;
      debugPrint('Spine: catalogue failed to load — $error');
      debugPrintStack(stackTrace: stack);
    }

    notifyListeners();
  }

  /// Changing ad cadence at runtime (e.g. from a remote config flag) recomposes
  /// the feed without touching the feed's own code, and without reshuffling the
  /// shelf.
  void updateAdConfig(AdConfig config) {
    _adConfig = config;
    if (_status == LibraryStatus.ready) {
      _compose();
      notifyListeners();
    }
  }

  void _arrange(BookProgress Function(String bookId) progressOf) {
    final now = _clock();
    _books = ShelfOrder.arrange(
      books: _catalogue,
      progressOf: progressOf,
      now: now,
    );
    _compose(now: now);
  }

  void _compose({DateTime? now}) {
    final today = DailyPicker.pick(books: _books, now: now ?? _clock());

    _feedItems = List.unmodifiable([
      if (today != null)
        DailyIdeaFeedItem(
          book: today.book,
          ideaIndex: today.ideaIndex,
          day: today.day,
        ),
      ..._reviewCards(),
      ...FeedComposer.compose(books: _books, config: _adConfig),
    ]);
  }

  /// Turns due review entries into cards, dropping any whose idea has since
  /// left the catalogue.
  List<ReviewFeedItem> _reviewCards() {
    final cards = <ReviewFeedItem>[];

    for (final item in _dueReviews) {
      final book = bookById(item.bookId);
      if (book == null) continue;

      final index = book.ideas.indexWhere((idea) => idea.id == item.ideaId);
      if (index < 0) continue;

      cards.add(
        ReviewFeedItem(book: book, ideaIndex: index, stage: item.stage),
      );
    }

    return cards;
  }

  /// Looks through the whole catalogue, not just the published shelf, so a
  /// saved book that has been pulled from the feed can still resolve.
  Book? bookById(String id) {
    for (final book in _catalogue) {
      if (book.id == id) return book;
    }
    return null;
  }

  /// Index of a book within the feed, so Search and Saved can open the shelf at
  /// the right card. Returns -1 when the book isn't on the shelf.
  int feedIndexOfBook(String id) =>
      _feedItems.indexWhere((item) => item is BookFeedItem && item.book.id == id);

  /// Title/author/genre/idea-title match, over published books. Cheap enough to
  /// run per keystroke: each book's haystack is built once at load.
  List<Book> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return _books;

    final terms = needle.split(RegExp(r'\s+'));
    return [
      for (final book in _books)
        if (terms.every((term) => (_searchIndex[book.id] ?? '').contains(term)))
          book,
    ];
  }
}
