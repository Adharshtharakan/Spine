import '../../data/models/book_progress.dart';
import '../../data/models/session_state.dart';

/// Local persistence for reader state.
///
/// Deliberately a narrow interface: a Firebase/Supabase-backed implementation
/// later only has to satisfy these four methods, and can sit behind the same
/// controller.
abstract interface class ProgressStore {
  Future<Map<String, BookProgress>> loadAll();

  Future<void> save(BookProgress progress);

  Future<SessionState> loadSession();

  Future<void> saveSession(SessionState session);
}

/// Non-persisting implementation — used by tests and as a safe fallback if
/// platform storage is unavailable at startup.
class InMemoryProgressStore implements ProgressStore {
  final Map<String, BookProgress> _entries = {};
  SessionState _session = const SessionState();

  @override
  Future<Map<String, BookProgress>> loadAll() async => Map.of(_entries);

  @override
  Future<void> save(BookProgress progress) async {
    _entries[progress.bookId] = progress;
  }

  @override
  Future<SessionState> loadSession() async => _session;

  @override
  Future<void> saveSession(SessionState session) async => _session = session;
}
