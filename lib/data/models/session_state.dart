/// Small app-level state that isn't tied to a single book: where the feed was
/// left, and the reading streak shown next to the wordmark.
class SessionState {
  const SessionState({
    this.lastBookId,
    this.streak = 0,
    this.lastActiveDay,
    this.dailyIdeaHour,
    this.brokenStreak = 0,
    this.lastRepairMonth,
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

  /// The streak that was lost to a single missed day, held so it can be
  /// offered back. Zero when there is nothing to repair.
  ///
  /// Only a one-day gap is repairable. Someone who missed a week didn't have
  /// the habit interrupted, they stopped — handing back a 40-day streak there
  /// would make the number mean nothing.
  final int brokenStreak;

  /// `yyyy-mm` of the last repair, which is what limits it to one a month.
  final String? lastRepairMonth;

  bool get wantsDailyIdea => dailyIdeaHour != null;

  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  /// Whether a repair is on the table right now.
  bool canRepair(DateTime now) =>
      brokenStreak > 0 && lastRepairMonth != monthKey(now);

  /// Restores the broken streak and counts today toward it.
  SessionState repair(DateTime now) {
    if (!canRepair(now)) return this;
    return SessionState(
      lastBookId: lastBookId,
      streak: brokenStreak + 1,
      lastActiveDay: dayKey(now),
      dailyIdeaHour: dailyIdeaHour,
      brokenStreak: 0,
      lastRepairMonth: monthKey(now),
    );
  }

  /// Drops the offer without using it up — for a reader who says no.
  SessionState declineRepair() => copyWith(clearBrokenStreak: true);

  SessionState copyWith({
    String? lastBookId,
    int? streak,
    String? lastActiveDay,
    int? dailyIdeaHour,
    bool clearDailyIdeaHour = false,
    int? brokenStreak,
    bool clearBrokenStreak = false,
    String? lastRepairMonth,
  }) {
    return SessionState(
      lastBookId: lastBookId ?? this.lastBookId,
      streak: streak ?? this.streak,
      lastActiveDay: lastActiveDay ?? this.lastActiveDay,
      dailyIdeaHour: clearDailyIdeaHour
          ? null
          : (dailyIdeaHour ?? this.dailyIdeaHour),
      brokenStreak: clearBrokenStreak ? 0 : (brokenStreak ?? this.brokenStreak),
      lastRepairMonth: lastRepairMonth ?? this.lastRepairMonth,
    );
  }

  Map<String, dynamic> toJson() => {
    'lastBookId': lastBookId,
    'streak': streak,
    'lastActiveDay': lastActiveDay,
    'dailyIdeaHour': dailyIdeaHour,
    'brokenStreak': brokenStreak,
    'lastRepairMonth': lastRepairMonth,
  };

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      lastBookId: json['lastBookId'] as String?,
      streak: json['streak'] as int? ?? 0,
      lastActiveDay: json['lastActiveDay'] as String?,
      dailyIdeaHour: json['dailyIdeaHour'] as int?,
      brokenStreak: json['brokenStreak'] as int? ?? 0,
      lastRepairMonth: json['lastRepairMonth'] as String?,
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
    if (lastActiveDay == yesterday) {
      return copyWith(streak: streak + 1, lastActiveDay: key);
    }

    // Exactly one day missed: the streak still resets, but what was lost is
    // remembered so it can be offered back once. Anything longer is a real
    // stop, and is not repairable at any price.
    final dayBefore = dayKey(today.subtract(const Duration(days: 2)));
    final missedOneDay = lastActiveDay == dayBefore && streak >= 2;

    return copyWith(
      streak: 1,
      lastActiveDay: key,
      brokenStreak: missedOneDay ? streak : 0,
      clearBrokenStreak: !missedOneDay,
    );
  }
}
