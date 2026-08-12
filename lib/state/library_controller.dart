import 'package:flutter/foundation.dart';

import '../core/config/ad_config.dart';
import '../data/models/book.dart';
import '../data/models/feed_item.dart';
import '../data/repository/book_repository.dart';
import '../services/ads/feed_composer.dart';

enum LibraryStatus { loading, ready, failed }

/// Owns the catalogue and the composed feed.
///
/// Everything downstream reads `feedItems`; nothing downstream knows whether an
/// entry is a book or an ad until it renders one.
class LibraryController extends ChangeNotifier {
  LibraryController({required BookRepository repository, required AdConfig adConfig})
    : _repository = repository,
      _adConfig = adConfig;

  final BookRepository _repository;
  AdConfig _adConfig;

  LibraryStatus _status = LibraryStatus.loading;
  Object? _error;
  List<Book> _books = const [];
  List<FeedItem> _feedItems = const [];
  final Map<String, String> _searchIndex = {};

  LibraryStatus get status => _status;
  Object? get error => _error;
  List<Book> get books => _books;
  List<FeedItem> get feedItems => _feedItems;
  AdConfig get adConfig => _adConfig;

  Future<void> load() async {
    _status = LibraryStatus.loading;
    notifyListeners();

    try {
      _books = await _repository.loadBooks();
      _searchIndex
        ..clear()
        ..addEntries(
          _books.map((book) => MapEntry(book.id, book.buildSearchIndex())),
        );
      _feedItems = FeedComposer.compose(books: _books, config: _adConfig);
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
  /// the feed without touching the feed's own code.
  void updateAdConfig(AdConfig config) {
    _adConfig = config;
    if (_status == LibraryStatus.ready) {
      _feedItems = FeedComposer.compose(books: _books, config: _adConfig);
      notifyListeners();
    }
  }

  Book? bookById(String id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  /// Index of a book within the feed, so Search and Saved can open the shelf at
  /// the right card.
  int feedIndexOfBook(String id) =>
      _feedItems.indexWhere((item) => item is BookFeedItem && item.book.id == id);

  /// Title/author/genre/idea-title match. Cheap enough to run per keystroke:
  /// each book's haystack is built once at load.
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
