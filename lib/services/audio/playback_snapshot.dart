enum PlaybackStatus { idle, loading, playing, paused, completed, failed }

/// An immutable read of the playhead. The UI never reaches into the player.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.trackId,
    this.bookId,
    this.ideaIndex = 0,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isSimulated = false,
  });

  static const idle = PlaybackSnapshot();

  final String? trackId;
  final String? bookId;
  final int ideaIndex;
  final PlaybackStatus status;
  final Duration position;

  /// Real duration once known, otherwise the catalogue's declared duration.
  final Duration duration;

  /// True when this track has no recorded narration and the playhead is being
  /// driven by a timer instead of an audio file.
  final bool isSimulated;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isLoading => status == PlaybackStatus.loading;
  bool get isActive =>
      status == PlaybackStatus.playing ||
      status == PlaybackStatus.paused ||
      status == PlaybackStatus.loading;

  /// 0..1 progress through the current track.
  double get fraction {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  bool isTrack(String? id) => id != null && id == trackId;

  PlaybackSnapshot copyWith({
    String? trackId,
    String? bookId,
    int? ideaIndex,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    bool? isSimulated,
  }) {
    return PlaybackSnapshot(
      trackId: trackId ?? this.trackId,
      bookId: bookId ?? this.bookId,
      ideaIndex: ideaIndex ?? this.ideaIndex,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isSimulated: isSimulated ?? this.isSimulated,
    );
  }
}
