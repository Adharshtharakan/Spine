import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../widgets/tap_scale.dart';

/// The share control, sized to sit in the footer band above the bottom nav.
///
/// Shared by both footers rather than written twice: Read and Listen put it
/// in the same place on screen, and it should stay the same size and weight
/// when the reader switches between them.
class StoryShareButton extends StatelessWidget {
  const StoryShareButton(
      {super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;

  /// Short devices tighten the whole card; the control shrinks with it, but
  /// not below a comfortable target.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Named, not a bare glyph: sharing an idea is the one thing on this card a
    // reader has no reason to guess at, and an icon alone was missed.
    // Scaled down rather than clipped: in Listen the pill shares its row with
    // the play control and has less width than in Read.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: TapScale(
        onTap: onTap,
        semanticLabel: 'Share this idea',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 18 : 22,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(32),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share_outlined, size: 19, color: palette.brass),
                const SizedBox(width: 11),
                Text(
                  'SHARE',
                  style: SpineText.labelMedium.copyWith(color: palette.brass),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
