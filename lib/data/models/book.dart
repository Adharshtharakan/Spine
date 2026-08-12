import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import 'idea.dart';

/// Whether an animated explainer exists for a book yet.
enum WatchAvailability { comingSoon, available }

/// The Watch mode's data, kept as its own object so that adding real video is
/// a content change (fill in `videoUrl`) rather than a code change.
class WatchTrack {
  const WatchTrack({
    this.availability = WatchAvailability.comingSoon,
    this.videoUrl,
    this.posterUrl,
    this.duration,
  });

  final WatchAvailability availability;
  final String? videoUrl;
  final String? posterUrl;
  final Duration? duration;

  bool get isAvailable =>
      availability == WatchAvailability.available &&
      (videoUrl?.isNotEmpty ?? false);

  factory WatchTrack.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WatchTrack();
    final seconds = (json['seconds'] as num?)?.toInt();
    return WatchTrack(
      availability: (json['available'] as bool? ?? false)
          ? WatchAvailability.available
          : WatchAvailability.comingSoon,
      videoUrl: json['videoUrl'] as String?,
      posterUrl: json['posterUrl'] as String?,
      duration: seconds == null ? null : Duration(seconds: seconds),
    );
  }
}

/// A book as Spine presents it: a cover, some metadata, and five ideas.
@immutable
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.genre,
    required this.durationLabel,
    required this.spineColor,
    required this.ideas,
    this.coverUrl,
    this.watch = const WatchTrack(),
  });

  final String id;
  final String title;
  final String author;
  final String genre;

  /// Human-readable total, e.g. "14 MIN" — shown on the cover chip.
  final String durationLabel;

  /// The signature colour: cover wash, ribbon fill, active controls.
  final Color spineColor;

  /// Optional cover artwork (`asset:` or `https:`). When absent the cover panel
  /// renders the spine-colour gradient from the prototype, which is the
  /// intended default look rather than a placeholder.
  final String? coverUrl;

  final List<Idea> ideas;
  final WatchTrack watch;

  int get ideaCount => ideas.length;

  bool get hasAnyAudio => ideas.any((idea) => idea.hasAudio);

  /// Total narrated runtime — used by the audio layer, not for display.
  Duration get totalDuration =>
      ideas.fold(Duration.zero, (sum, idea) => sum + idea.duration);

  Idea ideaAt(int index) => ideas[index.clamp(0, ideas.length - 1)];

  /// Everything search matches against. The library builds this once per book
  /// and keeps it, so typing never re-walks the catalogue's strings.
  String buildSearchIndex() => [
    title,
    author,
    genre,
    ...ideas.map((i) => i.title),
  ].join(' ').toLowerCase();

  factory Book.fromJson(Map<String, dynamic> json) {
    final rawIdeas = (json['ideas'] as List<dynamic>? ?? const []);
    return Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      genre: json['genre'] as String? ?? '',
      durationLabel: json['durationLabel'] as String? ?? '',
      spineColor: SpineColors.resolveSpine(json['spine'] as String? ?? 'brass'),
      coverUrl: json['cover'] as String?,
      watch: WatchTrack.fromJson(json['watch'] as Map<String, dynamic>?),
      ideas: [
        for (var i = 0; i < rawIdeas.length; i++)
          Idea.fromJson(rawIdeas[i] as Map<String, dynamic>, order: i),
      ],
    );
  }
}
