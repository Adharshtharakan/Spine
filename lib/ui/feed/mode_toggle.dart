import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/reading_mode.dart';
import '../widgets/tap_scale.dart';

/// READ · LISTEN · WATCH, as one segmented track.
///
/// A single recessed surface with a lit segment sliding across it, rather than
/// three outlined buttons — the control reads as one object with a state, which
/// is what it is.
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
    const modes = ReadingMode.values;
    final index = modes.indexOf(mode);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SpineColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / modes.length;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: segment * index,
                top: 0,
                bottom: 0,
                width: segment,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final value in modes)
                    Expanded(
                      child: _Segment(
                        mode: value,
                        selected: value == mode,
                        locked: value == ReadingMode.watch && watchLocked,
                        onTap: () => onSelect(value),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.mode,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final ReadingMode mode;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SpineColors.parchment : SpineColors.onInk(0.45);

    return TapScale(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: '${mode.label} mode',
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                mode.label,
                maxLines: 1,
                style: SpineText.label.copyWith(color: color),
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 5),
              Icon(Icons.lock_outline_rounded, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
