import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'audio_source_resolver.dart';
import 'audio_track.dart';
import 'playback_snapshot.dart';
import 'spine_audio_player.dart';

/// Real playback, backed by just_audio (ExoPlayer on Android, AVPlayer on iOS).
class JustAudioPlayer implements SpineAudioPlayer {
  JustAudioPlayer({required AudioSourceResolver resolver, ja.AudioPlayer? player})
    : _resolver = resolver,
      _player = player ?? ja.AudioPlayer() {
    _subscriptions.addAll([
      _player.positionStream.listen((position) {
        if (_snapshot.status == PlaybackStatus.idle) return;
        _emit(_snapshot.copyWith(position: position));
      }),
      _player.durationStream.listen((duration) {
        if (duration == null || duration == Duration.zero) return;
        _emit(_snapshot.copyWith(duration: duration));
      }),
      _player.playerStateStream.listen(_onPlayerState),
    ]);
  }

  final AudioSourceResolver _resolver;
  final ja.AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  PlaybackSnapshot _snapshot = PlaybackSnapshot.idle;

  /// Guards against a slow load finishing after the reader has swiped on.
  int _loadToken = 0;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> load(AudioTrack track, {Duration startAt = Duration.zero}) async {
    final token = ++_loadToken;

    _emit(
      PlaybackSnapshot(
        trackId: track.id,
        bookId: track.bookId,
        ideaIndex: track.ideaIndex,
        status: PlaybackStatus.loading,
        position: startAt,
        duration: track.expectedDuration,
      ),
    );

    try {
      final source = await _resolver.resolve(track);
      if (token != _loadToken) return;

      final duration = switch (source) {
        AssetAudioSource(:final assetPath) => await _player.setAsset(
          assetPath,
          initialPosition: startAt,
        ),
        FileAudioSource(:final path) => await _player.setFilePath(
          path,
          initialPosition: startAt,
        ),
        RemoteAudioSource(:final uri) => await _player.setUrl(
          uri.toString(),
          initialPosition: startAt,
        ),
        UnrecordedAudioSource() => null,
      };

      if (token != _loadToken) return;

      _emit(
        _snapshot.copyWith(
          status: PlaybackStatus.paused,
          duration: duration ?? track.expectedDuration,
        ),
      );
    } catch (error, stack) {
      if (token != _loadToken) return;
      debugPrint('Spine: audio load failed for ${track.id} — $error');
      debugPrintStack(stackTrace: stack);
      _emit(_snapshot.copyWith(status: PlaybackStatus.failed));
    }
  }

  @override
  Future<void> play() async {
    if (_snapshot.status == PlaybackStatus.idle) return;
    if (_snapshot.status == PlaybackStatus.completed) {
      await _player.seek(Duration.zero);
    }
    // Intentionally not awaited: play() completes only when playback finishes.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emit(_snapshot.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    _loadToken++;
    await _player.stop();
    _emit(PlaybackSnapshot.idle);
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _controller.close();
  }

  void _onPlayerState(ja.PlayerState state) {
    if (_snapshot.status == PlaybackStatus.idle) return;

    final status = switch (state.processingState) {
      ja.ProcessingState.idle => PlaybackStatus.idle,
      ja.ProcessingState.loading ||
      ja.ProcessingState.buffering => _snapshot.status == PlaybackStatus.playing
          ? PlaybackStatus.playing
          : PlaybackStatus.loading,
      ja.ProcessingState.ready =>
        state.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      ja.ProcessingState.completed => PlaybackStatus.completed,
    };

    _emit(_snapshot.copyWith(status: status));
  }

  void _emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
