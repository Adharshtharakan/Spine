import '../models/book.dart';

/// The catalogue, abstracted away from where it lives.
///
/// The MVP ships `AssetBookRepository` (a bundled JSON file). Moving to
/// Firebase/Supabase/an HTTP API later means adding an implementation here —
/// no screen, controller or widget needs to change.
abstract interface class BookRepository {
  /// The full catalogue, in shelf order.
  Future<List<Book>> loadBooks();
}
