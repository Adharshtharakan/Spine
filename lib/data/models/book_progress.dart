import 'package:flutter/foundation.dart';

import 'reading_mode.dart';

/// Everything Spine remembers about one book between launches.
class BookProgress {
  const BookProgress({
    required this.bookId,
    this.ideaIndex = 0,
    this.mode = ReadingMode.read,
    this.saved = false,
    this.notifyOnWatch = false,
    this.resumeAt = Duration.zero,
    this.completedIdeas = const <int>{},
    this.savedIdeaIds = const <String>{},
    this.highlights = const <String, List<String>>{},
  });

  final String bookId;

  /// Which idea the reader is on.
  final int ideaIndex;

  /// Read / Listen / Watch — remembered per book, as in the prototype.
  final ReadingMode mode;

  final bool saved;

  /// "Notify me" on the Watch panel.
  final bool notifyOnWatch;

  /// Playback position inside `ideaIndex`, so Listen resumes where it stopped.
  final Duration resumeAt;

  /// Indices of ideas heard/read all the way through — drives the ribbon fill
  /// and the reading-progress figure on the profile.
  final Set<int> completedIdeas;

  /// Ideas kept on their own, by idea id rather than by position: a saved idea
  /// outlives an edit that reorders the book, where the completion set (already
  /// shipped as indices) does not.
  final Set<String> savedIdeaIds;

  /// Lines kept out of an idea, by idea id.
  ///
  /// The sentence text is stored rather than an offset: an offset silently
  /// points at the wrong words the moment an idea is edited, where the text
  /// still shows what the reader actually kept. It is also what the Saved
  /// shelf and a story card need, so nothing has to re-derive it.
  final Map<String, List<String>> highlights;

  /// `mapEquals` compares the lists by identity, and two equal lists are never
  /// identical — so it reports every restored copy as different from the one it
  /// was built from. This walks into them.
  static bool _sameHighlights(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!listEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  bool isIdeaSaved(String ideaId) => savedIdeaIds.contains(ideaId);

  List<String> highlightsFor(String ideaId) =>
      highlights[ideaId] ?? const <String>[];

  bool isHighlighted(String ideaId, String line) =>
      highlightsFor(ideaId).contains(line);

  int get highlightCount =>
      highlights.values.fold(0, (sum, lines) => sum + lines.length);

  bool isFinished(int totalIdeas) =>
      totalIdeas > 0 && completedIdeas.length >= totalIdeas;

  bool get isStarted =>
      ideaIndex > 0 || completedIdeas.isNotEmpty || resumeAt > Duration.zero;

  double completionOf(int totalIdeas) =>
      totalIdeas == 0 ? 0 : completedIdeas.length / totalIdeas;

  BookProgress copyWith({
    int? ideaIndex,
    ReadingMode? mode,
    bool? saved,
    bool? notifyOnWatch,
    Duration? resumeAt,
    Set<int>? completedIdeas,
    Set<String>? savedIdeaIds,
    Map<String, List<String>>? highlights,
  }) {
    return BookProgress(
      bookId: bookId,
      ideaIndex: ideaIndex ?? this.ideaIndex,
      mode: mode ?? this.mode,
      saved: saved ?? this.saved,
      notifyOnWatch: notifyOnWatch ?? this.notifyOnWatch,
      resumeAt: resumeAt ?? this.resumeAt,
      completedIdeas: completedIdeas ?? this.completedIdeas,
      savedIdeaIds: savedIdeaIds ?? this.savedIdeaIds,
      highlights: highlights ?? this.highlights,
    );
  }

  // Value equality lets the feed rebuild a card only when that card's state
  // actually changed. `resumeAt` is excluded on purpose: it moves with the
  // playhead and would defeat the point.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookProgress &&
          other.bookId == bookId &&
          other.ideaIndex == ideaIndex &&
          other.mode == mode &&
          other.saved == saved &&
          other.notifyOnWatch == notifyOnWatch &&
          setEquals(other.completedIdeas, completedIdeas) &&
          setEquals(other.savedIdeaIds, savedIdeaIds) &&
          _sameHighlights(other.highlights, highlights);

  @override
  int get hashCode => Object.hash(
    bookId,
    ideaIndex,
    mode,
    saved,
    notifyOnWatch,
    completedIdeas.length,
    savedIdeaIds.length,
    highlightCount,
  );

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'ideaIndex': ideaIndex,
    'mode': mode.id,
    'saved': saved,
    'notifyOnWatch': notifyOnWatch,
    'resumeMs': resumeAt.inMilliseconds,
    'completed': completedIdeas.toList()..sort(),
    'savedIdeas': savedIdeaIds.toList()..sort(),
    if (highlights.isNotEmpty) 'highlights': highlights,
  };

  factory BookProgress.fromJson(Map<String, dynamic> json) {
    return BookProgress(
      bookId: json['bookId'] as String,
      ideaIndex: json['ideaIndex'] as int? ?? 0,
      mode: ReadingMode.fromId(json['mode'] as String?),
      saved: json['saved'] as bool? ?? false,
      notifyOnWatch: json['notifyOnWatch'] as bool? ?? false,
      resumeAt: Duration(milliseconds: json['resumeMs'] as int? ?? 0),
      completedIdeas: {
        for (final value in (json['completed'] as List<dynamic>? ?? const []))
          value as int,
      },
      highlights: {
        for (final entry
            in (json['highlights'] as Map<dynamic, dynamic>? ?? const {}).entries)
          entry.key as String: [
            for (final line in entry.value as List<dynamic>) line as String,
          ],
      },
      savedIdeaIds: {
        for (final value in (json['savedIdeas'] as List<dynamic>? ?? const []))
          value as String,
      },
    );
  }
}
