import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../../services/notifications/daily_idea_notifier.dart';
import '../../state/library_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/review_controller.dart';
import '../widgets/tap_scale.dart';

/// You. Deliberately thin: what you've read, and nothing that turns Spine into
/// a social product.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = context.watch<ProgressController>();
    final library = context.watch<LibraryController>();
    final config = context.read<AppConfig>();

    final totalIdeas = library.books.fold<int>(
      0,
      (sum, book) => sum + book.ideaCount,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.brass.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                'S',
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
                    'Reader',
                    style: SpineText.ideaHeading.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${progress.streak} DAY STREAK',
                    style: SpineText.label.copyWith(color: palette.brass),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            _Stat(value: '${progress.ideasCompleted}', label: 'Ideas'),
            const SizedBox(width: 10),
            _Stat(value: '${progress.booksStarted}', label: 'Started'),
            const SizedBox(width: 10),
            _Stat(
              value: '${context.watch<ReviewController>().queuedCount}',
              label: 'In review',
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _DailyIdeaSetting(),
        const SizedBox(height: 10),
        _Block(
          label: 'Your library',
          value: '${library.books.length} books · $totalIdeas ideas',
        ),
        const SizedBox(height: 10),
        const _AppearanceSetting(),
        const SizedBox(height: 10),
        _Block(
          label: 'About',
          value: config.isProd ? 'Spine' : 'Spine · ${config.environment}',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: SpineText.bookTitle.copyWith(fontSize: 30)),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: SpineText.labelSmall.copyWith(
                color: palette.onGround(0.42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: SpineText.labelSmall.copyWith(
              color: palette.onGround(0.42),
            ),
          ),
          const SizedBox(height: 8),
          Text(value, style: SpineText.ideaBody.copyWith(fontSize: 15)),
        ],
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THE DAY\'S IDEA',
            style: SpineText.labelSmall.copyWith(
              color: palette.onGround(0.42),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selected == null
                ? 'One idea, delivered. Off.'
                : 'One idea, delivered each day.',
            style: SpineText.ideaBody.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 14),
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
                  onTap: () => _choose(context, selected == hour ? null : hour),
                ),
            ],
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? palette.brass.withValues(alpha: 0.2)
              : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
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
    final palette = context.palette;
    final dark = context.select<ProgressController, bool>(
      (controller) => controller.darkMode,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APPEARANCE',
            style: SpineText.label.copyWith(color: palette.onGround(0.45)),
          ),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? palette.brass.withValues(alpha: 0.16)
              : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
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
