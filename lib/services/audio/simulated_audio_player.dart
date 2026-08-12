import 'dart:async';

import 'audio_track.dart';
import 'playback_snapshot.dart';
import 'spine_audio_player.dart';

/// A silent, timed playhead for ideas whose narration hasn't been recorded.
///
/// This is not a stand-in for the audio architecture — it satisfies the same
/// `SpineAudioPlayer` contract and is chosen per track by the engine. The
/// moment an idea gains an `audio` reference in the catalogue, that idea plays
/// through the real player instead, with no other change anywhere.
class SimulatedAudioPlayer implements SpineAudioPlayer {
  static const _tick = Duration(milliseconds: 100);

  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  PlaybackSnapshot _snapshot = PlaybackSnapshot.idle;
  Timer? _timer;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> load(AudioTrack track, {Duration startAt = Duration.zero}) async {
    _timer?.cancel();
    _emit(
      PlaybackSnapshot(
        trackId: track.id,
        bookId: track.bookId,
        ideaIndex: track.ideaIndex,
        status: PlaybackStatus.paused,
        position: startAt,
        duration: track.expectedDuration,
        isSimulated: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_snapshot.trackId == null) return;

    if (_snapshot.status == PlaybackStatus.completed) {
      _emit(_snapshot.copyWith(position: Duration.zero));
    }
    _emit(_snapshot.copyWith(status: PlaybackStatus.playing));

    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      final next = _snapshot.position + _tick;
      if (next >= _snapshot.duration) {
        _timer?.cancel();
        _emit(
          _snapshot.copyWith(
            position: _snapshot.duration,
            status: PlaybackStatus.completed,
          ),
        );
        return;
      }
      _emit(_snapshot.copyWith(position: next));
    });
  }

  @override
  Future<void> pause() async {
    _timer?.cancel();
    if (_snapshot.status == PlaybackStatus.playing) {
      _emit(_snapshot.copyWith(status: PlaybackStatus.paused));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _snapshot.duration ? _snapshot.duration : position);
    _emit(_snapshot.copyWith(position: clamped));
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _emit(PlaybackSnapshot.idle);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }

  void _emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
