import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import 'audio_source_resolver.dart';
import 'audio_track.dart';
import 'just_audio_player.dart';
import 'playback_snapshot.dart';
import 'simulated_audio_player.dart';
import 'spine_audio_player.dart';

/// The single audio surface for the app.
///
/// Spine only ever plays one thing at a time — a feed with two voices is a bug,
/// not a feature — so there is exactly one engine, owned by `PlaybackController`.
/// It routes each track to the real player or the timed fallback and republishes
/// both as one stream.
class SpineAudioEngine implements SpineAudioPlayer {
  SpineAudioEngine({
    required AudioSourceResolver resolver,
    SpineAudioPlayer? realPlayer,
    SpineAudioPlayer? fallbackPlayer,
  }) : _real = realPlayer ?? JustAudioPlayer(resolver: resolver),
       _fallback = fallbackPlayer ?? SimulatedAudioPlayer() {
    _subscriptions.addAll([
      _real.snapshots.listen((s) => _republish(_real, s)),
      _fallback.snapshots.listen((s) => _republish(_fallback, s)),
    ]);
  }

  final SpineAudioPlayer _real;
  final SpineAudioPlayer _fallback;
  final List<StreamSubscription<PlaybackSnapshot>> _subscriptions = [];
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  SpineAudioPlayer? _active;
  PlaybackSnapshot _snapshot = PlaybackSnapshot.idle;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  /// Configures the OS audio session: spoken-word playback that ducks other
  /// audio politely and honours the silent switch the way an audiobook should.
  static Future<void> configureSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (error) {
      debugPrint('Spine: audio session configuration failed — $error');
    }
  }

  @override
  Future<void> load(AudioTrack track, {Duration startAt = Duration.zero}) async {
    final target = track.hasSource ? _real : _fallback;

    // Release whichever player was previously holding the stage.
    if (_active != null && !identical(_active, target)) {
      await _active!.stop();
    }
    _active = target;

    await target.load(track, startAt: startAt);
  }

  @override
  Future<void> play() async => _active?.play();

  @override
  Future<void> pause() async => _active?.pause();

  @override
  Future<void> seek(Duration position) async => _active?.seek(position);

  @override
  Future<void> stop() async {
    await _active?.stop();
    _active = null;
    _emit(PlaybackSnapshot.idle);
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _real.dispose();
    await _fallback.dispose();
    await _controller.close();
  }

  void _republish(SpineAudioPlayer source, PlaybackSnapshot snapshot) {
    if (!identical(source, _active)) return;
    _emit(snapshot);
  }

  void _emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
