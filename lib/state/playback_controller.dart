import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/book.dart';
import '../services/audio/audio_track.dart';
import '../services/audio/playback_snapshot.dart';
import '../services/audio/spine_audio_player.dart';
import 'progress_controller.dart';

/// Drives Listen mode: one book at a time, one idea at a time, advancing
/// through the book on its own the way an audiobook chapter list does.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required SpineAudioPlayer engine,
    required ProgressController progress,
  }) : _engine = engine,
       _progress = progress {
    _subscription = _engine.snapshots.listen(_onSnapshot);
  }

  final SpineAudioPlayer _engine;
  final ProgressController _progress;
  late final StreamSubscription<PlaybackSnapshot> _subscription;

  Book? _book;
  bool _advancing = false;

  PlaybackSnapshot get snapshot => _engine.snapshot;
  Book? get book => _book;

  /// True when this exact idea is the one loaded in the engine.
  bool isCurrent(String bookId, int ideaIndex) {
    final s = snapshot;
    return s.bookId == bookId && s.ideaIndex == ideaIndex && s.isActive;
  }

  bool isPlayingBook(String bookId) =>
      snapshot.bookId == bookId && snapshot.isPlaying;

  /// Loads an idea, optionally starting it. Re-opening the idea that is already
  /// loaded is a no-op, so rebuilds and mode toggles never restart audio.
  Future<void> open(
    Book book,
    int ideaIndex, {
    bool autoplay = false,
    Duration? startAt,
  }) async {
    final idea = book.ideaAt(ideaIndex);
    final alreadyLoaded =
        snapshot.trackId == idea.id && snapshot.status != PlaybackStatus.idle;

    if (!alreadyLoaded) {
      _book = book;
      await _engine.load(
        AudioTrack(
          id: idea.id,
          bookId: book.id,
          ideaIndex: ideaIndex,
          expectedDuration: idea.duration,
          ref: idea.audioRef,
        ),
        startAt: startAt ?? _progress.of(book.id).resumeAt,
      );
    }

    if (autoplay) await _engine.play();
    notifyListeners();
  }

  Future<void> toggle(Book book, int ideaIndex) async {
    if (snapshot.bookId == book.id &&
        snapshot.ideaIndex == ideaIndex &&
        snapshot.isActive) {
      if (snapshot.isPlaying) {
        await _engine.pause();
        _persistPosition();
      } else {
        await _engine.play();
      }
      notifyListeners();
      return;
    }
    await open(book, ideaIndex, autoplay: true);
  }

  Future<void> seekFraction(double fraction) async {
    final total = snapshot.duration;
    if (total == Duration.zero) return;
    await _engine.seek(total * fraction.clamp(0.0, 1.0));
  }

  /// Called when the reader swipes to another card. Audio never follows the
  /// reader off the page.
  Future<void> stop() async {
    _persistPosition();
    _book = null;
    await _engine.stop();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!snapshot.isPlaying) return;
    await _engine.pause();
    _persistPosition();
    notifyListeners();
  }

  void _onSnapshot(PlaybackSnapshot snapshot) {
    final bookId = snapshot.bookId;
    if (snapshot.isPlaying && bookId != null) {
      _progress.setResumePosition(bookId, snapshot.ideaIndex, snapshot.position);
    }

    if (snapshot.status == PlaybackStatus.completed) {
      unawaited(_handleCompletion(snapshot));
    }

    notifyListeners();
  }

  /// End of an idea: bank the progress, then roll into the next one. At the end
  /// of the book playback simply stops — the reader is free to swipe on.
  Future<void> _handleCompletion(PlaybackSnapshot snapshot) async {
    final book = _book;
    if (book == null || _advancing) return;
    if (snapshot.bookId != book.id) return;

    _advancing = true;
    try {
      final finishedIndex = snapshot.ideaIndex;
      _progress.markIdeaComplete(book.id, finishedIndex);

      final nextIndex = finishedIndex + 1;
      if (nextIndex >= book.ideaCount) {
        _progress.setIdeaIndex(book.id, finishedIndex);
        return;
      }

      _progress.setIdeaIndex(book.id, nextIndex);
      await open(book, nextIndex, autoplay: true, startAt: Duration.zero);
    } finally {
      _advancing = false;
    }
  }

  void _persistPosition() {
    final s = snapshot;
    if (s.bookId == null) return;
    _progress.setResumePosition(s.bookId!, s.ideaIndex, s.position);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
