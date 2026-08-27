import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';

/// Turns one idea to the next like a page.
///
/// This is a perspective flip, not a paper curl. A true curl needs a deformed
/// mesh — a fragment shader or a custom `Canvas.drawVertices` — and the cost of
/// getting it right is out of proportion to a transition the reader sees for
/// 400ms. Rotating each page about its inner edge, with a shadow that deepens
/// as it goes, reads as a page turning and costs a matrix.
///
/// Direction follows the reader: forward turns the leaving page away to the
/// left, backward brings it back from the left.
class PageTurn extends StatelessWidget {
  const PageTurn({
    super.key,
    required this.child,
    required this.turnKey,
    required this.forward,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget child;

  /// Changing this is what starts a turn.
  final Object turnKey;

  /// Which way the reader is going.
  final bool forward;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      // The outgoing page has to finish leaving before the new one is done
      // arriving, or both are edge-on at once and the card looks empty.
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => _Leaf(
        animation: animation,
        forward: forward,
        child: child,
      ),
      child: KeyedSubtree(key: ValueKey(turnKey), child: child),
    );
  }
}

class _Leaf extends StatelessWidget {
  const _Leaf({
    required this.animation,
    required this.forward,
    required this.child,
  });

  final Animation<double> animation;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 0 while edge-on, 1 flat to the reader.
        final t = animation.value;

        // At rest the page is flat, so it is handed through untouched. A
        // perspective matrix left in place distorts hit testing — the
        // long-press that highlights a sentence lands at the wrong offset —
        // and there is nothing to see for the cost.
        if (t >= 1) return child;

        final angle = (1 - t) * (math.pi / 2) * (forward ? -1 : 1);

        return Transform(
          alignment: forward ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            // Perspective. Without this the rotation is an affine squash and
            // reads as a shrink rather than a turn.
            ..setEntry(3, 2, 0.0011)
            ..rotateY(angle),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              // The page darkens along the spine as it stands up, which is what
              // sells the fold — a flat rotation looks like a sliding card.
              IgnorePointer(
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0) * 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: forward
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: forward
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          palette.ground.withValues(alpha: 0.9),
                          palette.ground.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
