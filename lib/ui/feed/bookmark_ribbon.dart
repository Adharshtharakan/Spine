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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _RibbonPainter(
          body: palette.isDark
              ? accent.withValues(alpha: 0.22)
              : accent.withValues(alpha: 0.30),
          edge: accent.withValues(alpha: palette.isDark ? 0.45 : 0.55),
          stitch: palette.isDark ? palette.onGround(0.18) : accent,
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
    final ink = palette.isDark ? palette.text : palette.text;

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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final step = constraints.maxHeight / count;

        return Stack(
          children: [
            // The thread the stars are strung on, drawn behind them.
            Positioned(
              top: step / 2,
              bottom: step / 2,
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
  const _Star({
    required this.filled,
    required this.current,
    required this.colour,
    required this.dim,
  });

  final bool filled;
  final bool current;
  final Color colour;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    // The reader's own star is larger and brighter; it is the thing that
    // travels, so it has to be the thing the eye lands on.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: current ? 20 : 13,
      height: current ? 20 : 13,
      child: CustomPaint(
        painter: OrnamentStar(
          colour: filled ? colour : dim,
          filled: filled,
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

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    // Waist controls how sharp the points are: the closer to the centre, the
    // more it reads as a sparkle rather than a diamond.
    final waist = w * 0.16;

    final path = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx + waist, cy - waist, w, cy)
      ..quadraticBezierTo(cx + waist, cy + waist, cx, h)
      ..quadraticBezierTo(cx - waist, cy + waist, 0, cy)
      ..quadraticBezierTo(cx - waist, cy - waist, cx, 0)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.4,
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
    required this.edge,
    required this.stitch,
  });

  final Color body;
  final Color edge;
  final Color stitch;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const notch = 22.0;

    final shape = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - notch)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(shape, Paint()..color = body);
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
