import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/companion.dart';
import '../../services/notifications/daily_idea_notifier.dart';
import '../../state/library_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/review_controller.dart';
import '../../state/shell_controller.dart';
import '../widgets/hoot.dart';
import '../widgets/tap_scale.dart';

/// You. Deliberately thin: what you've read, and nothing that turns Spine into
/// a social product.
///
/// The one game-like thing on it is Hoot, and Hoot's rank comes from ideas
/// finished and nothing else — not opens, not time in the app, not streaks.
/// A companion that levels up for attendance says nothing about reading.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressController>();
    final library = context.watch<LibraryController>();
    final config = context.read<AppConfig>();

    final totalIdeas = library.books.fold<int>(
      0,
      (sum, book) => sum + book.ideaCount,
    );
    final read = progress.ideasCompleted;
    final level = CompanionLevel.forIdeas(read);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _Header(level: level),
        const SizedBox(height: 20),
        _CompanionCard(level: level),
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(
              value: '$read',
              label: 'Ideas',
              icon: Icons.lightbulb_outline_rounded,
            ),
            const SizedBox(width: 10),
            _Stat(
              value: '${progress.booksStarted}',
              label: 'Started',
              icon: Icons.menu_book_rounded,
            ),
            const SizedBox(width: 10),
            _Stat(
              value: '${context.watch<ReviewController>().queuedCount}',
              label: 'In review',
              icon: Icons.star_outline_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _DailyIdeaSetting(),
        const SizedBox(height: 14),
        _LibraryCard(
          books: library.books.length,
          ideas: totalIdeas,
          read: read,
        ),
        const SizedBox(height: 14),
        const _StreakRow(),
        const SizedBox(height: 14),
        const _AppearanceSetting(),
        const SizedBox(height: 14),
        _About(
          value: config.isProd ? 'Spine' : 'Spine · ${config.environment}',
        ),
      ],
    );
  }
}

/// A card. Every panel on this screen is one, so the shape lives in one place.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding, this.outlined = false});

  final Widget child;
  final EdgeInsets? padding;

  /// Hoot's card is drawn out from the rest with a hairline.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: outlined
            ? Border.all(color: palette.brass.withValues(alpha: 0.22))
            : null,
      ),
      child: child,
    );
  }
}

/// Small caps over a panel's contents.
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: SpineText.labelSmall.copyWith(
        color: context.palette.onGround(0.42),
      ),
    );
  }
}

/// Avatar, name, and where the reader stands. Tapping it renames them.
class _Header extends StatelessWidget {
  const _Header({required this.level});

  final CompanionLevel level;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = context.watch<ProgressController>();
    final name = progress.readerName;

    return TapScale(
      onTap: () => renameReader(context),
      semanticLabel: 'Change your name',
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: palette.brass.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              // The first letter of whatever they chose, so the avatar changes
              // with the name rather than staying stuck on the default's S.
              name.characters.first.toUpperCase(),
              style: SpineText.bookTitle.copyWith(
                fontSize: 24,
                color: palette.brass,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SpineText.ideaHeading.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${progress.streak} DAY STREAK',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpineText.label.copyWith(
                          color: palette.onGround(0.5),
                        ),
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: SpineText.label.copyWith(
                        color: palette.onGround(0.3),
                      ),
                    ),
                    Text(
                      level.title,
                      style: SpineText.label.copyWith(color: palette.brass),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: palette.onGround(0.35),
            size: 24,
          ),
        ],
      ),
    );
  }
}

/// Asks the reader what to call them.
///
/// Public so the shelf's empty state or onboarding could reach it later; there
/// is nothing screen-specific in it.
Future<void> renameReader(BuildContext context) async {
  final controller = context.read<ProgressController>();
  final chosen = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _RenameSheet(initial: controller.readerName),
  );

  // null is a dismissal; an empty string is a deliberate clear back to the
  // default, and the two must not be confused.
  if (chosen == null) return;
  controller.setReaderName(chosen);
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial});

  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _field = TextEditingController(
    text: context.read<ProgressController>().hasReaderName
        ? widget.initial
        // Not pre-filled with the default: a reader who has never set a name
        // would have to clear "Reader" before typing their own.
        : '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_field.text);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      // Lifts clear of the keyboard, which covers the field otherwise.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: palette.groundRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.onGround(0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'What should we call you?',
                style: SpineText.ideaHeading.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Only ever shown to you, and only here.',
                style: SpineText.secondary.copyWith(
                  color: palette.onGround(0.5),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _field,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: SpineText.ideaBody.copyWith(
                  fontSize: 17,
                  color: palette.text,
                ),
                cursorColor: palette.brass,
                decoration: InputDecoration(
                  hintText: 'Reader',
                  counterText: '',
                  hintStyle: SpineText.ideaBody.copyWith(
                    fontSize: 17,
                    color: palette.onGround(0.3),
                  ),
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: palette.brass, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SheetButton(
                      label: 'Save',
                      filled: true,
                      onTap: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: filled
              ? palette.brass.withValues(alpha: 0.2)
              : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ExcludeSemantics(
          child: Center(
            child: Text(
              label.toUpperCase(),
              style: SpineText.labelMedium.copyWith(
                color: filled ? palette.brass : palette.onGround(0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoot, and how far they have come together.
class _CompanionCard extends StatelessWidget {
  const _CompanionCard({required this.level});

  final CompanionLevel level;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final read = context.select<ProgressController, int>(
      (controller) => controller.ideasCompleted,
    );

    return _Card(
      outlined: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Reading when there is reading behind them, asleep on an empty
            // shelf — the character reacting to the actual state is the whole
            // reason to have one.
            Hoot(
              size: 56,
              pose: read == 0 ? HootPose.sleeping : HootPose.reading,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Meet Hoot,',
                    style: SpineText.ideaHeading.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'your reading companion.',
                    style: SpineText.ideaBody.copyWith(fontSize: 13, height: 1.3),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    level.isMaxed
                        ? 'You have read everything together.'
                        : 'Keep reading to level up together!',
                    style: SpineText.secondary.copyWith(
                      fontSize: 11.5,
                      height: 1.3,
                      color: palette.onGround(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: palette.onGround(0.10),
            ),
            const SizedBox(width: 12),
            _LevelColumn(level: level),
          ],
        ),
      ),
    );
  }
}

class _LevelColumn extends StatelessWidget {
  const _LevelColumn({required this.level});

  final CompanionLevel level;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: 86,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'LEVEL ${level.level}',
            style: SpineText.labelSmall.copyWith(color: palette.brass),
          ),
          const SizedBox(height: 4),
          Text(
            level.title,
            style: SpineText.ideaHeading.copyWith(
              fontSize: 15,
              color: palette.brass,
            ),
          ),
          const SizedBox(height: 10),
          _Bar(value: level.progress),
          const SizedBox(height: 6),
          Text(
            level.isMaxed
                ? '${level.xp} XP'
                : '${level.xpIntoLevel} / ${level.xpForLevel} XP',
            style: SpineText.meta.copyWith(
              fontSize: 10,
              color: palette.onGround(0.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin filled track. Used for both the level and the streak milestone.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, this.height = 5});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: palette.onGround(0.16)),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: palette.brass),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: _Card(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: SpineText.bookTitle.copyWith(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.brass.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: palette.brass),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _CardLabel(label),
          ],
        ),
      ),
    );
  }
}

/// The library, and how far through it the reader is.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.books,
    required this.ideas,
    required this.read,
  });

  final int books;
  final int ideas;
  final int read;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = ideas == 0 ? 0.0 : (read / ideas).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CardLabel('Your library')),
              TapScale(
                onTap: () => context.read<ShellController>().selectTab(
                  ShellController.shelfTab,
                ),
                semanticLabel: 'View all books',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'VIEW ALL',
                      style: SpineText.labelSmall.copyWith(
                        color: palette.brass,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: palette.brass,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$books books · $ideas ideas',
            style: SpineText.ideaBody.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 22,
                  color: palette.onGround(0.45),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        read == 0 ? 'Start anywhere.' : 'Keep going!',
                        style: SpineText.ideaHeading.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        read == 0
                            ? 'Every book is five ideas long.'
                            : "You've read $percent% of your library.",
                        style: SpineText.secondary.copyWith(
                          color: palette.onGround(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Ring(value: fraction, label: '$percent%'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A percentage read as an arc. Small enough that a bar would be a hairline.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 46,
      height: 46,
      child: CustomPaint(
        painter: _RingPainter(
          value: value,
          track: palette.onGround(0.10),
          fill: palette.brass,
        ),
        child: Center(
          child: Text(
            label,
            style: SpineText.labelSmall.copyWith(
              fontSize: 10,
              color: palette.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 4.0;
    final rect = Rect.fromLTWH(
      width / 2,
      width / 2,
      size.width - width,
      size.height - width,
    );

    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    if (value <= 0) return;
    canvas.drawArc(
      rect,
      // From twelve o'clock, clockwise, the way a dial is read.
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// The streak, what it is heading for, and the way in to the full list.
class _StreakRow extends StatelessWidget {
  const _StreakRow();

  /// Where the streak is going next. Close enough together at the start that
  /// there is always one in sight.
  static const milestones = <int>[5, 14, 30, 60, 100, 365];

  static int? nextMilestone(int streak) {
    for (final day in milestones) {
      if (streak < day) return day;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final streak = context.select<ProgressController, int>(
      (controller) => controller.streak,
    );
    final target = nextMilestone(streak);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The one solid block on the screen. The streak is the number the
            // reader is keeping, so it is the number that gets the weight.
            Container(
              width: 96,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: palette.brass.withValues(alpha: palette.isDark ? 0.9 : 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 18,
                    color: palette.groundRaised,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$streak',
                    style: SpineText.bookTitle.copyWith(
                      fontSize: 26,
                      color: palette.groundRaised,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'DAY STREAK',
                    style: SpineText.labelSmall.copyWith(
                      fontSize: 9,
                      color: palette.groundRaised.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: palette.surface,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CardLabel(
                      target == null ? 'Every milestone' : 'Next milestone',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      target == null
                          ? 'A year unbroken.'
                          : 'Read $target days in a row',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SpineText.ideaBody.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _Bar(
                            value: target == null ? 1 : streak / target,
                            height: 4,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          target == null ? 'DONE' : '$streak / $target',
                          style: SpineText.meta.copyWith(
                            fontSize: 10,
                            color: palette.onGround(0.45),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            TapScale(
              onTap: () => showAchievements(context),
              semanticLabel: 'Achievements',
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border(
                    left: BorderSide(color: palette.onGround(0.08)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 20,
                      color: palette.onGround(0.55),
                    ),
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'AWARDS',
                            style: SpineText.labelSmall.copyWith(
                              fontSize: 9,
                              color: palette.onGround(0.55),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: palette.onGround(0.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the achievements sheet.
class Achievement {
  const Achievement({
    required this.title,
    required this.detail,
    required this.earned,
  });

  final String title;
  final String detail;
  final bool earned;
}

/// Everything Spine counts, and whether it has happened yet.
///
/// Derived rather than stored: there is nothing here that could be true and
/// unrecorded, so keeping a second copy of it would only be a way to get the
/// two out of step.
List<Achievement> achievementsFor({
  required int streak,
  required int ideasRead,
  required int booksFinished,
}) {
  return [
    for (final day in _StreakRow.milestones)
      Achievement(
        title: '$day day streak',
        detail: 'Read on $day days in a row',
        earned: streak >= day,
      ),
    for (final count in const [1, 10, 50, 125])
      Achievement(
        title: count == 1 ? 'First idea' : '$count ideas',
        detail: count == 1
            ? 'Finish your first idea'
            : 'Finish $count ideas',
        earned: ideasRead >= count,
      ),
    for (final count in const [1, 5, 25])
      Achievement(
        title: count == 1 ? 'First book' : '$count books',
        detail: count == 1
            ? 'Finish all five ideas in a book'
            : 'Finish $count books',
        earned: booksFinished >= count,
      ),
  ];
}

Future<void> showAchievements(BuildContext context) {
  final progress = context.read<ProgressController>();
  final library = context.read<LibraryController>();

  final finished = library.books
      .where((book) => progress.of(book.id).isFinished(book.ideaCount))
      .length;

  final rows = achievementsFor(
    streak: progress.streak,
    ideasRead: progress.ideasCompleted,
    booksFinished: finished,
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _AchievementSheet(rows: rows),
  );
}

class _AchievementSheet extends StatelessWidget {
  const _AchievementSheet({required this.rows});

  final List<Achievement> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final earned = rows.where((row) => row.earned).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: palette.groundRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.onGround(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Achievements',
                    style: SpineText.ideaHeading.copyWith(fontSize: 22),
                  ),
                ),
                Text(
                  '$earned / ${rows.length}',
                  style: SpineText.label.copyWith(color: palette.brass),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: row.earned
                                ? palette.brass.withValues(alpha: 0.16)
                                : palette.surfaceRaised,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            row.earned
                                ? Icons.emoji_events_rounded
                                : Icons.lock_outline_rounded,
                            size: 17,
                            color: row.earned
                                ? palette.brass
                                : palette.onGround(0.3),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.title,
                                style: SpineText.ideaHeading.copyWith(
                                  fontSize: 15,
                                  color: row.earned
                                      ? palette.text
                                      : palette.onGround(0.5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                row.detail,
                                style: SpineText.secondary.copyWith(
                                  color: palette.onGround(0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one setting Spine has: when the day's idea arrives.
///
/// Off until chosen — the notification permission is requested at the moment
/// the reader asks for the notification, never on first launch.
class _DailyIdeaSetting extends StatelessWidget {
  const _DailyIdeaSetting();

  static const _times = <(String, int)>[
    ('Morning', 8),
    ('Midday', 13),
    ('Evening', 20),
  ];

  Future<void> _choose(BuildContext context, int? hour) async {
    final palette = context.palette;
    final progress = context.read<ProgressController>();

    if (hour != null && progress.dailyIdeaHour == null) {
      final granted = await context.read<IdeaNotifier>().requestPermission();
      if (!granted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: palette.groundRaised,
              content: Text(
                'Notifications are off in system settings',
                style: SpineText.label.copyWith(color: palette.text),
              ),
            ),
          );
        return;
      }
    }

    progress.setDailyIdeaHour(hour);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = context.select<ProgressController, int?>(
      (controller) => controller.dailyIdeaHour,
    );

    return _Card(
      child: Stack(
        children: [
          // Behind the copy rather than beside it, so the card keeps its full
          // width for the three chips on a narrow phone.
          Positioned(
            right: -6,
            top: 4,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: SizedBox(
                  width: 108,
                  height: 76,
                  child: CustomPaint(
                    painter: _SunrisePainter(ink: palette.onGround(0.30)),
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardLabel("The day's idea"),
              const SizedBox(height: 8),
              Text(
                selected == null
                    ? 'One idea, delivered. Off.'
                    : 'One idea, delivered each day.',
                style: SpineText.ideaBody.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 16),
              // Wraps rather than a Row: three chips plus large system type
              // overflows a narrow phone.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, hour) in _times)
                    _TimeChip(
                      label: label,
                      active: selected == hour,
                      onTap: () =>
                          _choose(context, selected == hour ? null : hour),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sun coming up behind two hills — the plate on the daily-idea card.
class _SunrisePainter extends CustomPainter {
  const _SunrisePainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    final sun = Offset(w * 0.5, h * 0.46);
    final r = w * 0.17;
    canvas.drawArc(
      Rect.fromCircle(center: sun, radius: r),
      math.pi,
      math.pi,
      false,
      line,
    );

    // Rays, fanned over the top half only: the sun is rising, not overhead.
    for (var i = 0; i <= 8; i++) {
      final angle = math.pi + math.pi * (i / 8);
      final from = Offset(
        sun.dx + math.cos(angle) * r * 1.35,
        sun.dy + math.sin(angle) * r * 1.35,
      );
      final to = Offset(
        sun.dx + math.cos(angle) * r * 1.75,
        sun.dy + math.sin(angle) * r * 1.75,
      );
      canvas.drawLine(from, to, line);
    }

    // Two hills in front of it, and the ground they stand on.
    for (final (peak, halfWidth) in [(0.34, 0.18), (0.64, 0.22)]) {
      canvas.drawPath(
        Path()
          ..moveTo(w * (peak - halfWidth), h * 0.80)
          ..lineTo(w * peak, h * 0.48)
          ..lineTo(w * (peak + halfWidth), h * 0.80),
        line,
      );
    }
    canvas.drawLine(
      Offset(w * 0.04, h * 0.80),
      Offset(w * 0.96, h * 0.80),
      line,
    );

    // A river running out from between them.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.48, h * 0.80)
        ..quadraticBezierTo(w * 0.58, h * 0.90, w * 0.46, h * 0.99),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _SunrisePainter old) => old.ink != ink;
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TapScale(
      onTap: onTap,
      semanticLabel: '$label notification',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? palette.brass.withValues(alpha: 0.2)
              : palette.groundRaised,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label.toUpperCase(),
          style: SpineText.labelSmall.copyWith(
            color: active ? palette.brass : palette.onGround(0.55),
          ),
        ),
      ),
    );
  }
}

/// Light or dark, kept per reader.
///
/// A segmented control rather than a switch: "dark mode: on" leaves a reader
/// guessing what off looks like, where two named options say it outright.
class _AppearanceSetting extends StatelessWidget {
  const _AppearanceSetting();

  @override
  Widget build(BuildContext context) {
    final dark = context.select<ProgressController, bool>(
      (controller) => controller.darkMode,
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Appearance'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'Paper',
                  icon: Icons.light_mode_outlined,
                  selected: !dark,
                  onTap: () =>
                      context.read<ProgressController>().setDarkMode(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeChip(
                  label: 'Ink',
                  icon: Icons.dark_mode_outlined,
                  selected: dark,
                  onTap: () =>
                      context.read<ProgressController>().setDarkMode(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = selected ? palette.brass : palette.onGround(0.55);

    return TapScale(
      onTap: onTap,
      semanticLabel: '$label mode',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? palette.brass.withValues(alpha: 0.16)
              : palette.groundRaised,
          borderRadius: BorderRadius.circular(26),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: SpineText.labelMedium.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('About'),
          const SizedBox(height: 8),
          Text(value, style: SpineText.ideaBody.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}
