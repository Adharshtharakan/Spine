import 'package:flutter/foundation.dart';

/// Which tab is showing, and the one cross-tab request the app needs: "open
/// the shelf on this book", used by Search and Saved.
class ShellController extends ChangeNotifier {
  static const shelfTab = 0;
  static const searchTab = 1;
  static const savedTab = 2;
  static const profileTab = 3;

  int _tabIndex = shelfTab;
  String? _pendingBookId;

  int get tabIndex => _tabIndex;
  String? get pendingBookId => _pendingBookId;

  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  void openBook(String bookId) {
    _pendingBookId = bookId;
    _tabIndex = shelfTab;
    notifyListeners();
  }

  /// The shelf claims the request once it has scrolled there.
  void consumePendingBook() {
    if (_pendingBookId == null) return;
    _pendingBookId = null;
    // No notification: this only clears a one-shot flag, and notifying here
    // would bounce the shelf into a second rebuild for nothing.
  }
}
