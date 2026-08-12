import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/reading_mode.dart';
import '../widgets/tap_scale.dart';

/// READ · LISTEN · WATCH 🔒
class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.mode,
    required this.accent,
    required this.onSelect,
    this.watchLocked = true,
  });

  final ReadingMode mode;
  final Color accent;
  final ValueChanged<ReadingMode> onSelect;
  final bool watchLocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (final value in ReadingMode.values) ...[
            if (value != ReadingMode.values.first) const SizedBox(width: 6),
            Expanded(
              child: _ModeButton(
                mode: value,
                selected: value == mode,
                accent: accent,
                locked: value == ReadingMode.watch && watchLocked,
                onTap: () => onSelect(value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.locked,
    required this.onTap,
  });

  final ReadingMode mode;
  final bool selected;
  final Color accent;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: '${mode.label} mode',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.13) : Colors.transparent,
          border: Border.all(color: selected ? accent : SpineColors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: SpineText.label.copyWith(
                  letterSpacing: 0.8,
                  color: selected
                      ? SpineColors.parchment
                      : SpineColors.parchmentDim,
                ),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_outline,
                size: 10,
                color: selected
                    ? SpineColors.parchment
                    : SpineColors.parchmentDim,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
