import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import 'tap_scale.dart';

/// The masthead: wordmark on the left, streak and search on the right.
///
/// No rule underneath — the feed runs up to the top of the screen, and the
/// masthead floats on it.
class SpineTopBar extends StatelessWidget {
  const SpineTopBar({
    super.key,
    required this.streak,
    this.onSearchTap,
    this.title = 'SPINE',
    this.trailing,
  });

  final int streak;
  final VoidCallback? onSearchTap;
  final String title;
  final Widget? trailing;

  /// Height below the status bar, so screens that need to clear the floating
  /// masthead can inset by exactly the right amount.
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 20, 14),
      child: Row(
        children: [
          Expanded(child: Text(title, style: SpineText.wordmark)),
          if (streak > 0) _StreakCapsule(streak: streak),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (onSearchTap != null) ...[
            const SizedBox(width: 10),
            TapScale(
              onTap: onSearchTap,
              semanticLabel: 'Search',
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: palette.onGround(0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StreakCapsule extends StatelessWidget {
  const _StreakCapsule({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: palette.brass.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: 13,
            color: palette.brass,
          ),
          const SizedBox(width: 5),
          Text(
            '$streak',
            style: SpineText.labelMedium.copyWith(color: palette.brass),
          ),
        ],
      ),
    );
  }
}
