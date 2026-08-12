import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';

/// The rounded, mono-type chip used for genre, duration, and status markers.
class SpinePill extends StatelessWidget {
  const SpinePill({
    super.key,
    required this.label,
    this.icon,
    this.foreground = SpineColors.parchmentDim,
    this.borderColor = SpineColors.line,
    this.background,
    this.dense = false,
  });

  /// A pill sitting on a book's spine-coloured cover panel: ink on a tinted
  /// border, per the prototype.
  const SpinePill.onCover({Key? key, required String label})
    : this(
        key: key,
        label: label,
        foreground: const Color(0xCC16140F),
        borderColor: const Color(0x5916140F),
      );

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color borderColor;
  final Color? background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: SpineText.label.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
