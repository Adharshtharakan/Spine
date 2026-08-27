import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';

/// Turns one idea to the next the way a leaf turns in a book.
///
/// The physics that matter, and that a cross-fade or a slide both miss:
///
///  * **A page folds, it does not pivot.** Spinning the whole sheet about the
///    spine is the obvious implementation and it does not read. Under
///    perspective the near edge is magnified by almost exactly as much as the
///    rotation foreshortens it, so for the first half of the turn nothing
///    appears to happen, and then the sheet goes edge-on and disappears. What
///    a hand actually does is catch the outer corner and drag it across: a
///    crease forms in the sheet and *travels*, with the part beyond it folded
///    back over the part before it.
///  * **It travels toward the spine**, which on this card is the bookmark
///    ribbon down the left edge. The fold starts at the outer edge and runs in
///    to the ribbon, uncovering the next page behind it from the outside in.
///  * **It is caught by a corner, so the crease leans.** The bottom of the
///    fold runs ahead of the top, because that is the corner under the thumb.
///    A dead-vertical crease reads as a wipe.
///  * **The fold never changes end.** Forward, the crease runs in to the
///    ribbon; backward it runs back out again — the same motion rewound.
///    Swapping ends by direction, which is what a naive implementation does,
///    makes going back look like a different object entirely.
///  * **Only one leaf moves.** Going forward, the page you are on folds away
///    and the next is revealed lying underneath. Going back, the previous page
///    unfolds on top of the one you are on. The other leaf is still.
///  * **You see the back of what folds over.** The reverse of a sheet is blank
///    stock catching the light, not the page's own words in mirror.
///
/// This is a rigid two-panel fold, not a curl. A real curl needs a deformed
/// mesh, and the cost of that is out of proportion to half a second of motion.
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
  Object? _leavingKey;
  bool _forward = true;

  @override
  void didUpdateWidget(PageTurn old) {
    super.didUpdateWidget(old);
    if (old.turnKey == widget.turnKey) return;

    _leaving = old.child;
    _leavingKey = old.turnKey;
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
        // Flat and still: hand the page through untouched, with nothing wrapped
        // round it. A clip or a transform left in place costs a layer on every
        // frame the reader is actually reading.
        if (leaving == null || !_controller.isAnimating) return widget.child;

        final t = Curves.easeInOut.transform(_controller.value);

        // Keyed apart so Flutter builds two elements rather than reusing one.
        // Without this the leaf that is supposedly being left behind gets
        // rebuilt with the new idea, and the turn animates one page against a
        // copy of itself — which looks like no motion at all, because both
        // sides are showing the same words.
        final current = KeyedSubtree(
          key: ValueKey(widget.turnKey),
          child: widget.child,
        );
        final previous = KeyedSubtree(
          key: ValueKey(_leavingKey),
          child: leaving,
        );

        // Forward: the page you were on folds away, the new one lies beneath.
        // Backward: the page you were on stays put, and the one you are
        // returning to unfolds onto it.
        final beneath = _forward ? current : previous;
        final moving = _forward ? previous : current;

        // Both run 0 (lying flat, nothing folded) to 1 (folded right over and
        // gone past the spine), so the fold is always drawn by the same code;
        // only the direction of travel through it differs.
        final lift = _forward ? t : 1 - t;

        return _Fold(lift: lift, beneath: beneath, moving: moving);
      },
    );
  }
}

/// The sheet mid-fold: a flat part, a folded-back part, and the page revealed
/// between them.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.lift,
    required this.beneath,
    required this.moving,
  });

  /// 0 lying flat, 1 folded right over.
  final double lift;

  /// The still page underneath.
  final Widget beneath;

  /// The page doing the folding.
  final Widget moving;

  /// How far the bottom of the crease runs ahead of the top, as a fraction of
  /// the page's width. This is the corner under the thumb.
  static const _lean = 0.13;

  /// Paper takes a warm shadow. Neutral black over cream stock desaturates it,
  /// and the folded panel came out looking like brushed metal.
  static const _shadow = Color(0xFF3A2E14);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // Where the crease is. Starts at the outer edge with none of the
          // sheet folded, finishes at the spine with all of it folded.
          final fold = width * (1 - lift);

          // The lean is widest mid-turn: the corner is picked up, swings ahead
          // and comes back into line as the fold lands on the spine.
          final lean = width * _lean * math.sin(lift * math.pi);

          // Deepest as the sheet stands up over the fold, gone at either end.
          final shade = math.sin(lift * math.pi).clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.passthrough,
            children: [
              // The page being uncovered, and only where it has been
              // uncovered. Clipping it is not an optimisation: an idea is
              // words on the card with no ground of its own, so left whole it
              // shows straight through the sheet lying on top of it and the
              // two pages render as one illegible overlay. Cutting both sides
              // of the crease means each half of the card carries exactly one
              // page, with no opaque backing that would have to match the
              // card's own gradient.
              ClipPath(
                clipper: _Revealed(fold: fold, lean: lean),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    beneath,
                    // What the raised sheet throws onto it. Falls away from
                    // the crease, outward — so the gradient is pinned to where
                    // the crease currently is, not to the edge of the card.
                    // Anchored to the box instead, the dark end sat off in the
                    // clipped-away half and no shadow ever reached the fold.
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(_x(fold, width), 0),
                            end: Alignment(_x(fold + width * 0.22, width), 0),
                            colors: [
                              // Light enough to read as a shadow. At full
                              // strength it covered a third of the new page in
                              // a grey slab and looked like a second panel
                              // rather than the first one's shadow.
                              _shadow.withValues(alpha: 0.22 * shade),
                              _shadow.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // The part of the sheet still lying flat, between spine and
              // crease. Its own words, the right way round.
              IgnorePointer(
                child: ClipPath(
                  clipper: _Flat(fold: fold, lean: lean),
                  child: moving,
                ),
              ),

              // The part folded back over it. Blank stock: the reverse of a
              // page does not carry the page's own text, and drawing it there
              // would show the words in mirror.
              IgnorePointer(
                child: ClipPath(
                  clipper: _FoldedBack(fold: fold, lean: lean, width: width),
                  // Stock first, then the light on it. A BoxDecoration drops
                  // its colour the moment it is given a gradient, so doing
                  // both at once left the panel a translucent wash with the
                  // page's own words legible straight through the back of it.
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(color: palette.groundRaised),
                        child: const SizedBox.expand(),
                      ),
                      // Light, not paint. Shading with a palette colour was
                      // invisible in Paper mode — cream laid over cream — and
                      // the fold read as a rectangle sliding about. Black and
                      // white work against whatever the sheet is.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          // Pinned crease to free edge, the same way the cast
                          // shadow is: this panel is a moving band, and a
                          // gradient measured off the card would slide about
                          // inside it as the fold travelled.
                          gradient: LinearGradient(
                            begin: Alignment(_x(fold, width), 0),
                            end: Alignment(_x(2 * fold - width, width), 0),
                            colors: [
                              // The crease is the high point and catches the
                              // room; the free edge has fallen away into
                              // shadow.
                              Colors.white.withValues(alpha: 0.16),
                              _shadow.withValues(alpha: 0.04),
                              _shadow.withValues(alpha: 0.26),
                            ],
                            stops: const [0, 0.4, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A horizontal offset in pixels as a gradient [Alignment] x, which runs -1 at
/// the left edge to 1 at the right.
double _x(double offset, double width) =>
    width == 0 ? 0 : (2 * offset / width) - 1;

/// The wedge of the sheet still lying flat: spine to crease.
class _Flat extends CustomClipper<Path> {
  const _Flat({required this.fold, required this.lean});

  final double fold;
  final double lean;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(fold + lean, 0)
    ..lineTo(fold - lean, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_Flat old) => old.fold != fold || old.lean != lean;
}

/// Everything beyond the crease, where the page underneath has been uncovered.
class _Revealed extends CustomClipper<Path> {
  const _Revealed({required this.fold, required this.lean});

  final double fold;
  final double lean;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(fold + lean, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(fold - lean, size.height)
    ..close();

  @override
  bool shouldReclip(_Revealed old) => old.fold != fold || old.lean != lean;
}

/// The folded-back panel: the far side of the crease, reflected across it.
///
/// The reflection is taken about the vertical, not about the leaning crease
/// itself — the exact mirror of a tilted line is a rotation, and at these
/// angles the difference is a pixel or two against the cost of doing it
/// properly.
class _FoldedBack extends CustomClipper<Path> {
  const _FoldedBack({
    required this.fold,
    required this.lean,
    required this.width,
  });

  final double fold;
  final double lean;
  final double width;

  @override
  Path getClip(Size size) {
    // The sheet's outer edge, brought back across the crease.
    final free = 2 * fold - width;
    return Path()
      ..moveTo(fold + lean, 0)
      ..lineTo(free + lean, 0)
      ..lineTo(free - lean, size.height)
      ..lineTo(fold - lean, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_FoldedBack old) =>
      old.fold != fold || old.lean != lean || old.width != width;
}
