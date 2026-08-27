import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';

/// Spine's signature: a bookmark hanging into the page, carrying the reader's
/// place inside it.
///
/// The old ribbon was a 4px rail — decorative, and easy to miss entirely. This
/// is an object: it has a body, a stitched edge, a swallowtail, and the idea
/// counter printed on it. One star per idea runs down its length, and the
/// filled one travels downward as the reader advances, so position is read from
/// the bookmark rather than from a line of text.
class BookmarkRibbon extends StatelessWidget {
  const BookmarkRibbon({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.accent,
    required this.onSelect,
    this.completed = const <int>{},
    this.compact = false,
  });

  final int count;
  final int currentIndex;

  /// The book's own colour. Every book on paper would otherwise look identical,
  /// which is the complaint the covers exist to answer in dark mode.
  final Color accent;

  final ValueChanged<int> onSelect;
  final Set<int> completed;
  final bool compact;

  /// Width of the ribbon itself. The card's text column starts to the right of
  /// this, so it is part of the page's left margin rather than an overlay.
  static const width = 58.0;

  /// The ribbon's own colour, tinted by the book but never so far that it
  /// stops reading as a paper bookmark.
  Color _body(SpinePalette palette) {
    final tint = HSLColor.fromColor(accent);
    final base = HSLColor.fromColor(palette.ribbon);
    return base
        .withHue(tint.hue)
        .withSaturation((base.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _RibbonPainter(
          // The mockup's bookmark is a printed object, not a wash: an opaque
          // warm body with the weave showing through it.
          body: _body(palette),
          shade: _body(palette).withValues(alpha: 0.0),
          edge: palette.ribbonEdge,
          stitch: palette.isDark
              ? palette.onGround(0.22)
              : palette.ribbonEdge.withValues(alpha: 0.8),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, compact ? 14 : 20, 0, 36),
          child: Column(
            children: [
              _Counter(
                index: currentIndex,
                total: count,
                accent: accent,
                compact: compact,
              ),
              SizedBox(height: compact ? 12 : 18),
              Expanded(
                child: _Stars(
                  count: count,
                  currentIndex: currentIndex,
                  completed: completed,
                  accent: accent,
                  onSelect: onSelect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "IDEA / 1 / OF 5", stacked, printed onto the ribbon.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.index,
    required this.total,
    required this.accent,
    required this.compact,
  });

  final int index;
  final int total;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Printed on the ribbon, so it takes its contrast from the ribbon's own
    // body rather than from the page behind it.
    final ink = palette.isDark ? palette.text : const Color(0xFF3A2E14);

    return ExcludeSemantics(
      child: Column(
        children: [
          Text(
            'IDEA',
            style: SpineText.labelSmall.copyWith(
              color: ink.withValues(alpha: 0.55),
              fontSize: 9,
            ),
          ),
          // The number changes as the reader moves, so it counts up rather than
          // cutting — the same motion the stars make just below it.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '${index + 1}',
              key: ValueKey(index),
              style: SpineText.ideaHeading.copyWith(
                fontSize: compact ? 22 : 26,
                height: 1.1,
                color: ink,
              ),
            ),
          ),
          Text(
            'OF $total',
            style: SpineText.labelSmall.copyWith(
              color: ink.withValues(alpha: 0.55),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

/// One star per idea, spaced down the ribbon and joined by a thread.
///
/// The filled star is the reader's place. It moves down as they advance, which
/// is the whole point: progress you can see at a glance without reading a
/// number.
class _Stars extends StatelessWidget {
  const _Stars({
    required this.count,
    required this.currentIndex,
    required this.completed,
    required this.accent,
    required this.onSelect,
  });

  final int count;
  final int currentIndex;
  final Set<int> completed;
  final Color accent;
  final ValueChanged<int> onSelect;

  /// Kept clear at the bottom for the swallowtail.
  static const _footRoom = 26.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        // The run stops short of the foot: the swallowtail is cut out of the
        // ribbon there, and a star sitting in the notch reads as a mistake.
        // On a short ribbon — Listen mode, a small screen — a fixed 26 is a
        // large share of the column and squeezes the run unevenly, so it gives
        // way proportionally.
        final foot = math.min(_footRoom, height * 0.12);
        final usable = math.max(height - foot, 0.0);
        final step = usable / count;

        // Stars are drawn to whatever the spacing will carry. At the fixed
        // slot they collided on a short ribbon, and stars overlapping their
        // neighbours is exactly what reads as uneven spacing — the gaps are
        // even, but the shapes are not.
        final slot = math.min(_Star.slot, step);

        return Stack(
          children: [
            // The thread the stars are strung on, drawn behind them. It spans
            // the centres of the first and last star, not the whole column, or
            // it pokes out past both ends.
            Positioned(
              top: step / 2,
              bottom: foot + step / 2,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 1,
                  child: ColoredBox(color: accent.withValues(alpha: 0.35)),
                ),
              ),
            ),
            for (var i = 0; i < count; i++)
              Positioned(
                top: step * i,
                height: step,
                left: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  selected: i == currentIndex,
                  label: 'Idea ${i + 1}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Center(
                      child: _Star(
                        // Behind the reader, or read: solid. Ahead: an outline
                        // waiting to be filled.
                        filled: i <= currentIndex || completed.contains(i),
                        current: i == currentIndex,
                        colour: accent,
                        dim: palette.onGround(0.30),
                        slotSize: slot,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Star extends StatelessWidget {
  /// What a star is drawn at when the ribbon has room for it. Every star in a
  /// ribbon gets the same box whatever its state.
  static const slot = 19.0;

  const _Star({
    required this.filled,
    required this.current,
    required this.colour,
    required this.dim,
    required this.slotSize,
  });

  final bool filled;
  final bool current;
  final Color colour;
  final Color dim;

  /// What this ribbon can actually carry, which on a short one is less than
  /// [slot].
  final double slotSize;

  @override
  Widget build(BuildContext context) {
    // The reader's own star is larger and brighter; it is the thing that
    // travels, so it has to be the thing the eye lands on.
    //
    // Scaled, not resized. Growing the box moved the star within its slot and
    // pushed the gaps around it out of step — the spacing looked wrong on
    // whichever card happened to be on screen.
    return SizedBox(
      width: slotSize,
      height: slotSize,
      child: AnimatedScale(
        scale: current ? 1.0 : 0.68,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          painter: OrnamentStar(colour: filled ? colour : dim, filled: filled),
        ),
      ),
    );
  }
}

/// A four-pointed star — the ornament the design uses throughout, rather than
/// Material's five-pointed one, which reads as a rating.
class OrnamentStar extends CustomPainter {
  const OrnamentStar({required this.colour, this.filled = true});

  final Color colour;
  final bool filled;

  /// How thick an unfilled star is drawn.
  static const _stroke = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // A stroke straddles the line it follows, so an outline star drawn on the
    // same path as a filled one comes out half a stroke wider all round. Next
    // to each other down a ribbon that reads as the unfilled ones being a
    // different size from the filled ones — which is exactly the inconsistency
    // it looks like. Inset the outline instead, so both fill the same box.
    final inset = filled ? 0.0 : _stroke / 2;
    final left = inset;
    final top = inset;
    final right = w - inset;
    final bottom = h - inset;
    final cx = w / 2;
    final cy = h / 2;

    // Waist controls how sharp the points are: the closer to the centre, the
    // more it reads as a sparkle rather than a diamond.
    final waist = (right - left) * 0.16;

    final path = Path()
      ..moveTo(cx, top)
      ..quadraticBezierTo(cx + waist, cy - waist, right, cy)
      ..quadraticBezierTo(cx + waist, cy + waist, cx, bottom)
      ..quadraticBezierTo(cx - waist, cy + waist, left, cy)
      ..quadraticBezierTo(cx - waist, cy - waist, cx, top)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant OrnamentStar old) =>
      old.colour != colour || old.filled != filled;
}

/// The ribbon's silhouette: a body with a swallowtail cut from its foot, and a
/// stitched line just inside the edge.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({
    required this.body,
    required this.shade,
    required this.edge,
    required this.stitch,
  });

  final Color body;
  final Color shade;
  final Color edge;
  final Color stitch;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const notch = 22.0;
    const head = 10.0;

    // Rounded at the head, square down the sides, swallowtailed at the foot.
    final shape = Path()
      ..moveTo(0, head)
      ..quadraticBezierTo(0, 0, head, 0)
      ..lineTo(w - head, 0)
      ..quadraticBezierTo(w, 0, w, head)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - notch)
      ..lineTo(0, h)
      ..close();

    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(shape, Paint()..color = body);

    // A woven grain, printed into the body. Two crossing sets of hairlines at
    // very low contrast: enough to read as cloth up close, invisible as
    // pattern at arm's length.
    final weave = Paint()
      ..color = edge.withValues(alpha: 0.16)
      ..strokeWidth = 0.7;
    for (var d = -h; d < w + h; d += 7) {
      canvas.drawLine(Offset(d, 0), Offset(d + h, h), weave);
      canvas.drawLine(Offset(d + h, 0), Offset(d, h), weave);
    }

    // The fold shadow down the inner edge, so it sits on the page rather than
    // in it.
    canvas.drawRect(
      Rect.fromLTWH(w - 6, 0, 6, h),
      Paint()
        ..shader = LinearGradient(
          colors: [shade, edge.withValues(alpha: 0.28)],
        ).createShader(Rect.fromLTWH(w - 6, 0, 6, h)),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // A dashed line inside the edge, the way a bookmark is stitched.
    final inset = Path()
      ..moveTo(6, 0)
      ..lineTo(6, h - notch * 0.55)
      ..moveTo(w - 6, 0)
      ..lineTo(w - 6, h - notch * 0.55);

    canvas.drawPath(
      _dashed(inset),
      Paint()
        ..color = stitch.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  Path _dashed(Path source, {double on = 4, double off = 5}) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + on).clamp(0.0, metric.length);
        out.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.body != body || old.edge != edge || old.stitch != stitch;
}
