/// Hoot's rank, and how far along it the reader is.
///
/// Spine has one number worth counting — ideas finished — so that is the only
/// thing this is derived from. Nothing here can be earned by opening the app,
/// tapping around or holding a streak, because a companion that levels up for
/// attendance stops meaning anything about reading.
///
/// XP is that same count presented at ten to the idea: a bar that moves by a
/// tenth of its width per idea reads as progress, where one that moves by a
/// thirtieth reads as stuck.
class CompanionLevel {
  const CompanionLevel._({
    required this.level,
    required this.title,
    required this.xp,
    required this.xpIntoLevel,
    required this.xpForLevel,
  });

  /// 1 upward.
  final int level;

  /// What Hoot is called at this rank.
  final String title;

  /// Total earned, across every level.
  final int xp;

  /// Earned since this level began.
  final int xpIntoLevel;

  /// What this level costs in total, or null at the last one.
  final int? xpForLevel;

  /// What an idea is worth.
  static const xpPerIdea = 10;

  /// Where each rank starts, in XP.
  static const _ranks = <(int, String)>[
    (0, 'Novice'),
    (300, 'Reader'),
    (750, 'Scholar'),
    (1400, 'Sage'),
    (2300, 'Owl'),
  ];

  factory CompanionLevel.forIdeas(int ideasCompleted) {
    final xp = ideasCompleted.clamp(0, 1 << 30) * xpPerIdea;

    var index = 0;
    for (var i = _ranks.length - 1; i >= 0; i--) {
      if (xp >= _ranks[i].$1) {
        index = i;
        break;
      }
    }

    final floor = _ranks[index].$1;
    final ceiling = index + 1 < _ranks.length ? _ranks[index + 1].$1 : null;

    return CompanionLevel._(
      level: index + 1,
      title: _ranks[index].$2,
      xp: xp,
      xpIntoLevel: xp - floor,
      xpForLevel: ceiling == null ? null : ceiling - floor,
    );
  }

  /// Nothing left to climb.
  bool get isMaxed => xpForLevel == null;

  /// 0 to 1 across the current level. Full at the top rank rather than empty:
  /// a finished bar reads as arrived, an empty one as never started.
  double get progress {
    final total = xpForLevel;
    if (total == null || total <= 0) return 1;
    return (xpIntoLevel / total).clamp(0.0, 1.0);
  }
}
