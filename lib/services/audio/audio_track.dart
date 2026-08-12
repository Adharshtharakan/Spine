/// A single playable unit of narration: one idea.
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.bookId,
    required this.ideaIndex,
    required this.expectedDuration,
    this.ref,
  });

  /// Stable id (the idea id) — used to tell snapshots apart.
  final String id;

  final String bookId;
  final int ideaIndex;

  /// Duration declared by the catalogue. Used for layout before the real file
  /// reports its length, and as the runtime for un-narrated ideas.
  final Duration expectedDuration;

  /// `asset:`, `file:`, or `http(s):` reference. Null when this idea has no
  /// narration recorded yet.
  final String? ref;

  bool get hasSource => ref != null && ref!.isNotEmpty;
}

/// Where a track's bytes actually come from, after resolution.
sealed class AudioSourceDescriptor {
  const AudioSourceDescriptor();
}

class AssetAudioSource extends AudioSourceDescriptor {
  const AssetAudioSource(this.assetPath);
  final String assetPath;
}

class FileAudioSource extends AudioSourceDescriptor {
  const FileAudioSource(this.path);
  final String path;
}

class RemoteAudioSource extends AudioSourceDescriptor {
  const RemoteAudioSource(this.uri);
  final Uri uri;
}

/// No narration for this idea (yet). The engine falls back to a timed,
/// silent playhead so the Listen UI still behaves correctly.
class UnrecordedAudioSource extends AudioSourceDescriptor {
  const UnrecordedAudioSource();
}
