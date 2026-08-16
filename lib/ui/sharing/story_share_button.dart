import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../widgets/tap_scale.dart';

/// The share control, sized to sit in the footer band above the bottom nav.
///
/// Shared by both footers rather than written twice: Read and Listen put it
/// in the same place on screen, and it should stay the same size and weight
/// when the reader switches between them.
class StoryShareButton extends StatelessWidget {
  const StoryShareButton({super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;

  /// Short devices tighten the whole card; the control shrinks with it, but
  /// not below a comfortable target.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 46.0 : 52.0;

    return TapScale(
      onTap: onTap,
      semanticLabel: 'Share this idea',
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: SpineColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.ios_share_rounded,
          size: compact ? 20 : 22,
          color: SpineColors.onInk(0.75),
        ),
      ),
    );
  }
}
