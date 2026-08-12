import 'audio_track.dart';
import 'playback_snapshot.dart';

/// The audio contract the app codes against.
///
/// Two implementations ship: `JustAudioPlayer` (real files, bundled or remote)
/// and `SimulatedAudioPlayer` (a timed playhead for ideas that have no
/// narration yet). `SpineAudioEngine` picks between them per track, so callers
/// only ever see this interface.
abstract interface class SpineAudioPlayer {
  /// Latest state, emitted on every meaningful change.
  Stream<PlaybackSnapshot> get snapshots;

  PlaybackSnapshot get snapshot;

  /// Loads a track and leaves it paused at [startAt].
  Future<void> load(AudioTrack track, {Duration startAt = Duration.zero});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Releases the current track and returns to idle.
  Future<void> stop();

  Future<void> dispose();
}
