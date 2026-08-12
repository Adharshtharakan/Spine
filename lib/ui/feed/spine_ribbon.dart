import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';

/// Spine's signature element: the vertical bookmark ribbon down the left edge.
///
/// One segment per idea. Segments behind you are full, the current one fills as
/// you listen, and any segment can be tapped to jump.
class SpineRibbon extends StatelessWidget {
  const SpineRibbon({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.color,
    required this.onSelect,
    this.currentFill = 0.35,
    this.completed = const <int>{},
    this.width = 10,
  });

  final int count;
  final int currentIndex;
  final Color color;
  final ValueChanged<int> onSelect;

  /// Fill of the current segment, 0..1. Listen mode drives this from the
  /// playhead; Read mode uses a resting sliver so the position stays legible.
  final double currentFill;

  final Set<int> completed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 3),
              Expanded(
                child: _Segment(
                  fill: _fillFor(i),
                  color: color,
                  index: i,
                  isCurrent: i == currentIndex,
                  onTap: () => onSelect(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _fillFor(int index) {
    if (index < currentIndex || completed.contains(index)) return 1;
    if (index == currentIndex) return currentFill.clamp(0.0, 1.0);
    return 0;
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.fill,
    required this.color,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  final double fill;
  final Color color;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isCurrent,
      label: 'Idea ${index + 1}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: ColoredBox(
            color: SpineColors.onInk(0.12),
            // Linear and short: the ribbon reads as a level filling, not as an
            // animation playing.
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
    );
  }
}
