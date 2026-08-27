import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';

/// Which of Hoot's poses to show.
///
/// The names match the sheet the character was drawn on, so a slice can be
/// exported straight to `assets/mascot/hoot_<name>.png` without anyone having
/// to work out the mapping.
enum HootPose {
  reading,
  excited,
  thinking,
  sleeping,
  idea,
  celebrating,

  /// The head only, for a small round frame.
  avatar;

  String get asset => 'assets/mascot/hoot_$name.png';
}

/// Spine's reading companion.
///
/// The artwork is optional. Until the slices are dropped into
/// `assets/mascot/`, this draws Hoot itself — a plain owl in the app's own
/// colours rather than a broken-image box or a gap where the character should
/// be. Nothing else in the app has to know which of the two it got.
class Hoot extends StatelessWidget {
  const Hoot({super.key, required this.size, this.pose = HootPose.reading});

  final double size;
  final HootPose pose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        pose.asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Called for a missing asset as well as a corrupt one, which is what
        // makes shipping without the artwork safe.
        errorBuilder: (context, _, __) => _DrawnHoot(pose: pose),
      ),
    );
  }
}

/// The stand-in: a round owl built from circles, in the palette's own brass.
///
/// Deliberately simple. Something half-rendered would read as the real
/// character drawn badly; this reads as a mark.
class _DrawnHoot extends StatelessWidget {
  const _DrawnHoot({required this.pose});

  final HootPose pose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CustomPaint(
      painter: _HootPainter(
        body: palette.brass.withValues(alpha: palette.isDark ? 0.30 : 0.22),
        ink: palette.brass,
        eye: palette.groundRaised,
        asleep: pose == HootPose.sleeping,
      ),
    );
  }
}

class _HootPainter extends CustomPainter {
  const _HootPainter({
    required this.body,
    required this.ink,
    required this.eye,
    required this.asleep,
  });

  final Color body;
  final Color ink;
  final Color eye;
  final bool asleep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final fill = Paint()..color = body;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(w * 0.022, 1)
      ..strokeCap = StrokeCap.round;

    // Ear tufts, before the body so they read as behind it.
    for (final side in [-1, 1]) {
      final x = cx + side * w * 0.20;
      canvas.drawPath(
        Path()
          ..moveTo(x - side * w * 0.06, h * 0.24)
          ..lineTo(x + side * w * 0.02, h * 0.08)
          ..lineTo(x + side * w * 0.10, h * 0.26)
          ..close(),
        fill,
      );
    }

    // A body wider than it is tall below the head, so it reads as a small
    // round owl rather than an egg.
    canvas.drawOval(Rect.fromLTWH(w * 0.14, h * 0.20, w * 0.72, h * 0.70), fill);

    // The glasses, which are the character.
    final lensR = w * 0.155;
    final lensY = h * 0.46;
    for (final side in [-1, 1]) {
      final centre = Offset(cx + side * w * 0.165, lensY);
      canvas.drawCircle(centre, lensR, Paint()..color = eye);
      canvas.drawCircle(centre, lensR, line);
      if (asleep) {
        // Closed: a lid across the lens, not a smaller circle.
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: lensR * 0.62),
          0,
          math.pi,
          false,
          line,
        );
      } else {
        canvas.drawCircle(centre, lensR * 0.42, Paint()..color = ink);
      }
    }
    // The bridge between them.
    canvas.drawLine(
      Offset(cx - w * 0.01, lensY),
      Offset(cx + w * 0.01, lensY),
      line,
    );

    // Beak.
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.045, lensY + lensR * 0.75)
        ..lineTo(cx + w * 0.045, lensY + lensR * 0.75)
        ..lineTo(cx, lensY + lensR * 1.5)
        ..close(),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(covariant _HootPainter old) =>
      old.body != body ||
      old.ink != ink ||
      old.eye != eye ||
      old.asleep != asleep;
}
