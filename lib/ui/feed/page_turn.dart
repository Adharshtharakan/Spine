import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';

/// Turns one idea to the next the way a leaf turns in a book.
///
/// The physics that matter, and that a cross-fade or a slide both miss:
///
///  * **The hinge never moves.** A page is bound at the spine, so it pivots
///    about the same edge whichever way you go. Swapping the hinge by
///    direction — which is what a naive implementation does — makes going back
///    look like a different object entirely.
///  * **Only one leaf moves.** Going forward, the page you are on lifts and
///    swings away, and the next page is simply revealed lying underneath it.
///    Going back, the previous page swings down on top of the one you are on.
///    The other leaf is still.
///  * **The leaf shades as it stands up**, and casts onto the page beneath.
///    Without that it reads as a rotating rectangle rather than paper.
///
/// This is a rigid leaf, not a curl. A real curl needs a deformed mesh, and
/// the cost of that is out of proportion to half a second of motion.
class PageTurn extends StatefulWidget {
  const PageTurn({
    super.key,
    required this.child,
    required this.turnKey,
    required this.forward,
    this.duration = const Duration(milliseconds: 520),
  });

  final Widget child;

  /// Changing this turns the page.
  final Object turnKey;

  /// Which way the reader is going.
  final bool forward;

  final Duration duration;

  @override
  State<PageTurn> createState() => _PageTurnState();
}

class _PageTurnState extends State<PageTurn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// The page being left behind, held only for as long as the turn lasts.
  Widget? _leaving;
  bool _forward = true;

  @override
  void didUpdateWidget(PageTurn old) {
    super.didUpdateWidget(old);
    if (old.turnKey == widget.turnKey) return;

    _leaving = old.child;
    _forward = widget.forward;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final leaving = _leaving;
        // Flat and still: hand the page through untouched. A perspective matrix
        // left in place distorts hit testing, and the long-press that
        // highlights a sentence lands at the wrong offset.
        if (leaving == null || !_controller.isAnimating) return widget.child;

        final t = Curves.easeInOut.transform(_controller.value);

        // Forward: the page you were on lifts away, the new one lies beneath.
        // Backward: the page you were on stays put, and the one you are
        // returning to swings down onto it.
        final beneath = _forward ? widget.child : leaving;
        final moving = _forward ? leaving : widget.child;

        // Both run 0 (flat) to 1 (edge-on), so the leaf is always drawn by the
        // same code; only the direction of travel through it differs.
        final lift = _forward ? t : 1 - t;

        return Stack(
          fit: StackFit.passthrough,
          children: [
            _Beneath(lift: lift, child: beneath),
            _Leaf(lift: lift, child: moving),
          ],
        );
      },
    );
  }
}

/// The still page, with the moving leaf's shadow sweeping across it.
class _Beneath extends StatelessWidget {
  const _Beneath({required this.lift, required this.child});

  final double lift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        // Deepest when the leaf is halfway up — that is when it is closest to
        // standing over this page. Gone by the time it is flat or edge-on.
        IgnorePointer(
          child: Opacity(
            opacity: math.sin(lift * math.pi) * 0.30,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0, 0.7],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The leaf in flight: hinged at the spine, shading as it stands up.
class _Leaf extends StatelessWidget {
  const _Leaf({required this.lift, required this.child});

  /// 0 flat on the page, 1 standing edge-on at the spine.
  final double lift;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Transform(
      // The spine. Fixed, both directions — this is the whole point.
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        // Without perspective the rotation is an affine squash and reads as a
        // shrink rather than a turn.
        ..setEntry(3, 2, 0.0012)
        ..rotateY(-lift * math.pi / 2),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    // Darkest at the spine, where a lifted page catches least
                    // light, easing out across the leaf.
                    palette.ground.withValues(alpha: 0.85 * lift),
                    palette.ground.withValues(alpha: 0.10 * lift),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
