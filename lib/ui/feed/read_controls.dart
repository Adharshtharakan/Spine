import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../widgets/tap_scale.dart';

/// PREV / NEXT under an idea in Read mode.
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
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavButton(label: 'Prev', enabled: canGoBack, onTap: onPrev),
          _NavButton(
            label: 'Next',
            enabled: canGoForward,
            onTap: onNext,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tinted = accent != null && enabled;

    return TapScale(
      onTap: onTap,
      enabled: enabled,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: tinted ? accent!.withValues(alpha: 0.13) : Colors.transparent,
          border: Border.all(
            color: tinted ? accent! : SpineColors.line,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label.toUpperCase(),
          style: SpineText.labelMedium.copyWith(
            color: enabled ? SpineColors.parchment : SpineColors.parchmentDim,
          ),
        ),
      ),
    );
  }
}
