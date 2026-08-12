/// Small app-level state that isn't tied to a single book: where the feed was
/// left, and the reading streak shown next to the wordmark.
class SessionState {
  const SessionState({
    this.feedIndex = 0,
    this.streak = 0,
    this.lastActiveDay,
  });

  final int feedIndex;

  /// Consecutive days with any reading activity. Deliberately the only
  /// game-like number in the app — it already exists in the prototype.
  final int streak;

  /// `yyyy-mm-dd` of the last day the app was opened.
  final String? lastActiveDay;

  SessionState copyWith({int? feedIndex, int? streak, String? lastActiveDay}) {
    return SessionState(
      feedIndex: feedIndex ?? this.feedIndex,
      streak: streak ?? this.streak,
      lastActiveDay: lastActiveDay ?? this.lastActiveDay,
    );
  }

  Map<String, dynamic> toJson() => {
    'feedIndex': feedIndex,
    'streak': streak,
    'lastActiveDay': lastActiveDay,
  };

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      feedIndex: json['feedIndex'] as int? ?? 0,
      streak: json['streak'] as int? ?? 0,
      lastActiveDay: json['lastActiveDay'] as String?,
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
