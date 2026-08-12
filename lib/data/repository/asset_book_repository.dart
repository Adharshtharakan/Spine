import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/book.dart';
import 'book_repository.dart';

/// Loads the catalogue from a bundled JSON manifest.
///
/// Adding books is a data edit — drop entries into `assets/content/books.json`
/// (or point `SPINE_CONTENT` at another manifest). Nothing in the UI knows how
/// many books exist, so 5 → 50 → 500 needs no code change.
class AssetBookRepository implements BookRepository {
  AssetBookRepository({
    required this.manifestPath,
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  final String manifestPath;
  final AssetBundle _bundle;

  List<Book>? _cache;

  @override
  Future<List<Book>> loadBooks() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _bundle.loadString(manifestPath);
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final entries = decoded['books'] as List<dynamic>? ?? const [];

    final books = [
      for (final entry in entries) Book.fromJson(entry as Map<String, dynamic>),
    ];

    return _cache = List.unmodifiable(books);
  }
}
