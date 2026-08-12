import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../widgets/tap_scale.dart';

/// PREV / NEXT under an idea in Read mode.
///
/// Filled surfaces rather than outlines, with a chevron so the direction reads
/// before the word does. Next carries the book's colour; Prev stays quiet.
class ReadControls extends StatelessWidget {
  const ReadControls({
    super.key,
    required this.accent,
    required this.canGoBack,
    required this.canGoForward,
    required this.onPrev,
    required this.onNext,
  });

  final Color accent;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _NavButton(
          label: 'Prev',
          icon: Icons.arrow_back_rounded,
          enabled: canGoBack,
          onTap: onPrev,
        ),
        _NavButton(
          label: 'Next',
          icon: Icons.arrow_forward_rounded,
          iconTrailing: true,
          enabled: canGoForward,
          onTap: onNext,
          accent: accent,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.accent,
    this.iconTrailing = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color? accent;
  final bool iconTrailing;

  @override
  Widget build(BuildContext context) {
    final tinted = accent != null && enabled;
    final foreground = enabled
        ? (tinted ? SpineColors.parchment : SpineColors.onInk(0.72))
        : SpineColors.onInk(0.3);

    final content = [
      Icon(icon, size: 15, color: foreground),
      const SizedBox(width: 8),
      Text(
        label.toUpperCase(),
        style: SpineText.labelMedium.copyWith(color: foreground),
      ),
    ];

    return TapScale(
      onTap: onTap,
      enabled: enabled,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: tinted
              ? accent!.withValues(alpha: 0.26)
              : SpineColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconTrailing ? content.reversed.toList() : content,
        ),
      ),
    );
  }
}
