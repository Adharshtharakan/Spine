import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';

/// The rounded, mono-type chip used for status markers.
///
/// Filled, never outlined: a chip is a small raised surface, and a stroke
/// around it would be the one border in a design that has none.
class SpinePill extends StatelessWidget {
  const SpinePill({
    super.key,
    required this.label,
    this.icon,
    this.foreground,
    this.background,
    this.dense = false,
  });

  /// A pill tinted with a book's own colour.
  SpinePill.accent({
    super.key,
    required this.label,
    required Color accent,
    this.icon,
    this.dense = false,
  }) : foreground = accent,
       background = accent.withValues(alpha: 0.16);

  final String label;
  final IconData? icon;
  /// Null falls back to the palette's own label and surface colours, resolved
  /// at build so the pill follows the mode being read.
  final Color? foreground;
  final Color? background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = foreground ?? palette.textDim;
    final bg = background ?? palette.surface;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: SpineText.label.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
