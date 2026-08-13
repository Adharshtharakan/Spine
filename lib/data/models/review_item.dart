/// One idea waiting to come back.
///
/// Spine's review is deliberately ungraded: there's no "I got it wrong" button,
/// no score, no streak to lose. Recalling an idea and then seeing it again is
/// the whole mechanism — the schedule just decides when.
class ReviewItem {
  const ReviewItem({
    required this.ideaId,
    required this.bookId,
    required this.dueAt,
    this.stage = 0,
  });

  final String ideaId;
  final String bookId;

  /// When this idea should next appear in the feed.
  final DateTime dueAt;

  /// How many times it has come back. Indexes into [ReviewSchedule.intervals].
  final int stage;

  bool isDue(DateTime now) => !dueAt.isAfter(now);

  ReviewItem copyWith({DateTime? dueAt, int? stage}) => ReviewItem(
    ideaId: ideaId,
    bookId: bookId,
    dueAt: dueAt ?? this.dueAt,
    stage: stage ?? this.stage,
  );

  Map<String, dynamic> toJson() => {
    'ideaId': ideaId,
    'bookId': bookId,
    'dueAt': dueAt.toIso8601String(),
    'stage': stage,
  };

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
    ideaId: json['ideaId'] as String,
    bookId: json['bookId'] as String,
    dueAt: DateTime.parse(json['dueAt'] as String),
    stage: json['stage'] as int? ?? 0,
  );
}

/// The expanding schedule an idea moves through.
abstract final class ReviewSchedule {
  /// Days until an idea returns, per stage. Roughly the standard expanding
  /// pattern: soon enough to catch it before it fades, then further apart each
  /// time. After the last stage an idea is considered learned and retires.
  static const intervals = <int>[2, 6, 14, 30, 90];

  static bool isRetired(int stage) => stage >= intervals.length;

  /// The next due date after a review at [stage], or null once retired.
  static DateTime? nextDue(int stage, DateTime from) {
    if (isRetired(stage)) return null;
    final days = intervals[stage];
    return DateTime(from.year, from.month, from.day + days, from.hour, from.minute);
  }
}
