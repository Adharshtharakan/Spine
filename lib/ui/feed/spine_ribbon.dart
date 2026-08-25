import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';

/// Spine's signature element: the vertical bookmark ribbon.
///
/// One segment per idea. Segments behind you are full, the current one fills as
/// you listen, and any segment can be tapped to jump. It now runs inside the
/// card's margin rather than clinging to the screen edge, so it reads as a
/// bookmark laid alongside the text.
class SpineRibbon extends StatelessWidget {
  const SpineRibbon({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.color,
    required this.onSelect,
    this.currentFill = 0,
    this.showPlayhead = false,
    this.completed = const <int>{},
    this.width = 4,
  });

  final int count;
  final int currentIndex;
  final Color color;
  final ValueChanged<int> onSelect;

  /// Fill of the current segment, 0..1, when [showPlayhead] is set.
  final double currentFill;

  /// Listen mode fills the current segment from the playhead. Read mode instead
  /// lights the whole segment at half strength — a partial bar would imply a
  /// progress that reading doesn't measure.
  final bool showPlayhead;

  final Set<int> completed;

  /// Width of the drawn bar. The column around it is wider so there's something
  /// to hit.
  final double width;

  static const _touchWidth = 22.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _touchWidth,
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Expanded(
              child: _Segment(
                fill: _fillFor(i),
                color: i == currentIndex && !showPlayhead
                    ? color.withValues(alpha: 0.5)
                    : color,
                index: i,
                isCurrent: i == currentIndex,
                width: width,
                onTap: () => onSelect(i),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _fillFor(int index) {
    if (index < currentIndex || completed.contains(index)) return 1;
    if (index != currentIndex) return 0;
    return showPlayhead ? currentFill.clamp(0.0, 1.0) : 1;
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.fill,
    required this.color,
    required this.index,
    required this.isCurrent,
    required this.width,
    required this.onTap,
  });

  final double fill;
  final Color color;
  final int index;
  final bool isCurrent;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: isCurrent,
      label: 'Idea ${index + 1}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The bar is hairline-thin by design; the transparent padding around it
        // is what makes it tappable.
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (SpineRibbon._touchWidth - width) / 2,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width),
            child: ColoredBox(
              color: palette.onGround(isCurrent ? 0.16 : 0.09),
              // Linear and short: the ribbon reads as a level filling, not as
              // an animation playing.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fill),
                duration: const Duration(milliseconds: 150),
                curve: Curves.linear,
                builder: (context, value, _) => Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    widthFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
