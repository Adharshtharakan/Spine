/// Small app-level state that isn't tied to a single book: where the feed was
/// left, and the reading streak shown next to the wordmark.
class SessionState {
  const SessionState({
    this.lastBookId,
    this.streak = 0,
    this.lastActiveDay,
    this.dailyIdeaHour,
  });

  /// The book the reader was last on. Stored by id rather than by feed position
  /// because the shelf reorders between sessions — position 4 is not the same
  /// card tomorrow.
  final String? lastBookId;

  /// Consecutive days with any reading activity. Deliberately the only
  /// game-like number in the app — it already exists in the prototype.
  final int streak;

  /// `yyyy-mm-dd` of the last day the app was opened.
  final String? lastActiveDay;

  /// Hour of the day the reader wants their idea, or null for no notification.
  /// Off by default: Spine asks for the permission only once it has been
  /// chosen, never on first launch.
  final int? dailyIdeaHour;

  bool get wantsDailyIdea => dailyIdeaHour != null;

  SessionState copyWith({
    String? lastBookId,
    int? streak,
    String? lastActiveDay,
    int? dailyIdeaHour,
    bool clearDailyIdeaHour = false,
  }) {
    return SessionState(
      lastBookId: lastBookId ?? this.lastBookId,
      streak: streak ?? this.streak,
      lastActiveDay: lastActiveDay ?? this.lastActiveDay,
      dailyIdeaHour: clearDailyIdeaHour
          ? null
          : (dailyIdeaHour ?? this.dailyIdeaHour),
    );
  }

  Map<String, dynamic> toJson() => {
    'lastBookId': lastBookId,
    'streak': streak,
    'lastActiveDay': lastActiveDay,
    'dailyIdeaHour': dailyIdeaHour,
  };

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      lastBookId: json['lastBookId'] as String?,
      streak: json['streak'] as int? ?? 0,
      lastActiveDay: json['lastActiveDay'] as String?,
      dailyIdeaHour: json['dailyIdeaHour'] as int?,
    );
  }

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Rolls the streak forward for [today]: same day keeps it, the next day
  /// extends it, any longer gap starts again at one.
  SessionState touch(DateTime today) {
    final key = dayKey(today);
    if (lastActiveDay == key) {
      return streak == 0 ? copyWith(streak: 1) : this;
    }
    final yesterday = dayKey(today.subtract(const Duration(days: 1)));
    return copyWith(
      streak: lastActiveDay == yesterday ? streak + 1 : 1,
      lastActiveDay: key,
    );
  }
}
