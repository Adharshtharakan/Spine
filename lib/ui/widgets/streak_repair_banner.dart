import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../state/progress_controller.dart';
import 'tap_scale.dart';

/// Offers back a streak lost to one missed day.
///
/// Losing a long streak to a single day is the point most people quit a habit
/// app, and the number is not worth keeping if it costs the reader. One repair
/// a month is enough to survive an ordinary bad day without making the streak
/// meaningless — a longer lapse is never repairable.
///
/// Declining spends nothing: the month's repair stays available for a lapse the
/// reader actually minds.
class StreakRepairBanner extends StatelessWidget {
  const StreakRepairBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final streak = context.select<ProgressController, int>(
      (controller) => controller.repairableStreak,
    );
    if (streak == 0) return const SizedBox.shrink();

    final controller = context.read<ProgressController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: SpineColors.inkCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SpineColors.brass.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR $streak-DAY STREAK',
                    style: SpineText.labelSmall.copyWith(
                      color: SpineColors.brass,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You missed a day. Put it back?',
                    style: SpineText.ideaBody.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
            TapScale(
              onTap: controller.declineStreakRepair,
              semanticLabel: 'Dismiss streak repair',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'NO',
                  style: SpineText.labelSmall.copyWith(
                    color: SpineColors.onInk(0.45),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            TapScale(
              onTap: controller.repairStreak,
              semanticLabel: 'Restore streak',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: SpineColors.brass,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'RESTORE',
                  style: SpineText.labelSmall.copyWith(color: SpineColors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
