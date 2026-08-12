import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import 'tap_scale.dart';

/// The masthead: wordmark on the left, streak and search on the right.
class SpineTopBar extends StatelessWidget {
  const SpineTopBar({
    super.key,
    required this.streak,
    this.onSearchTap,
    this.title = 'Spine',
    this.trailing,
  });

  final int streak;
  final VoidCallback? onSearchTap;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpineColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Row(
          children: [
            Expanded(child: Text(title, style: SpineText.wordmark)),
            if (streak > 0) ...[
              const Icon(
                Icons.local_fire_department,
                size: 16,
                color: SpineColors.brass,
              ),
              const SizedBox(width: 4),
              Text(
                '$streak',
                style: SpineText.meta.copyWith(color: SpineColors.brass),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 14), trailing!],
            if (onSearchTap != null) ...[
              const SizedBox(width: 14),
              TapScale(
                onTap: onSearchTap,
                semanticLabel: 'Search',
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.search,
                    size: 20,
                    color: SpineColors.parchmentDim,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
