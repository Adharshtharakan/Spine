import 'package:flutter/material.dart';

/// DriveSync brand colours.
abstract final class Brand {
  static const blue = Color(0xFF1F6FEB);
  static const navy = Color(0xFF0B2E6B);
  static const amber = Color(0xFFFFB020);
  static const amberDeep = Color(0xFFE08A00);
}

/// The DriveSync mark: a bold "D" with a car driving inside its curve, on a
/// blue tile. Drawn in code so the in-app logo and every launcher icon
/// (generated from this painter by `tool/gen_icons_test.dart`) are identical
/// and stay crisp at any size.
class DriveSyncMarkPainter extends CustomPainter {
  const DriveSyncMarkPainter({
    this.background = true,
    this.roundedTile = true,
    this.monochrome = false,
    this.glyphScale = 1.0,
    this.glyph = true,
  });

  /// Paint the D-and-car glyph (off for an adaptive icon's background layer).
  final bool glyph;

  /// Paint the blue tile behind the glyph.
  final bool background;

  /// Round the tile's corners (off for iOS icons, which the OS masks).
  final bool roundedTile;

  /// Single-colour white glyph (Android 13 themed icons).
  final bool monochrome;

  /// Shrinks the glyph inside the canvas (Android adaptive-icon safe zone).
  final double glyphScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    if (background) {
      final tile = Offset.zero & Size(s, s);
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F80FF), Brand.blue, Brand.navy],
          stops: [0, 0.45, 1],
        ).createShader(tile);
      if (roundedTile) {
        canvas.drawRRect(RRect.fromRectAndRadius(tile, Radius.circular(s * 0.23)), paint);
      } else {
        canvas.drawRect(tile, paint);
      }
      // Soft highlight across the top for depth.
      final gloss = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0)],
        ).createShader(tile);
      final glossPath = Path()..addRRect(RRect.fromRectAndRadius(tile, Radius.circular(roundedTile ? s * 0.23 : 0)));
      canvas.drawPath(glossPath, gloss);
    }

    if (!glyph) {
      canvas.restore();
      return;
    }

    // Glyph in a 100×100 design space.
    canvas.translate(s / 2, s / 2);
    canvas.scale(s / 100 * glyphScale);
    canvas.translate(-50, -50);

    final white = Paint()..color = Colors.white;

    // The D: straight stem on the left, a half-round bowl on the right, and
    // an open counter where the car sits.
    final d = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(20, 18)
      ..lineTo(50, 18)
      ..arcToPoint(const Offset(50, 82), radius: const Radius.circular(32))
      ..lineTo(20, 82)
      ..close()
      ..moveTo(33, 31)
      ..lineTo(50, 31)
      ..arcToPoint(const Offset(50, 69), radius: const Radius.circular(19))
      ..lineTo(33, 69)
      ..close();
    if (!monochrome && background) {
      canvas.drawPath(d.shift(const Offset(0, 1.6)), Paint()..color = Brand.navy.withValues(alpha: 0.35));
    }
    canvas.drawPath(d, white);

    // The car sits in the D's counter, slightly smaller than the opening.
    canvas.save();
    canvas.translate(52, 54);
    canvas.scale(0.88);
    canvas.translate(-52, -54);
    // Monochrome: draw on a layer so windows and hubs can be cut out.
    if (monochrome) canvas.saveLayer(null, Paint());

    // Road line the car drives on.
    final road = Paint()
      ..color = monochrome ? Colors.white : Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(37, 63.5), const Offset(66, 63.5), road);

    // Car, side view, facing right.
    final bodyColor = monochrome ? Colors.white : Brand.amber;
    final body = Path()
      ..moveTo(36.5, 60)
      ..lineTo(36.5, 55.5)
      ..quadraticBezierTo(36.8, 52.6, 40, 52)
      ..lineTo(44.5, 51.3)
      ..lineTo(49, 45.6)
      ..quadraticBezierTo(50, 44.6, 51.6, 44.6)
      ..lineTo(58.6, 44.6)
      ..quadraticBezierTo(60.2, 44.6, 61.2, 45.8)
      ..lineTo(65.2, 51.4)
      ..quadraticBezierTo(68.4, 52.2, 68.8, 55)
      ..lineTo(68.8, 60)
      ..quadraticBezierTo(68.8, 61.2, 67.6, 61.2)
      ..lineTo(37.7, 61.2)
      ..quadraticBezierTo(36.5, 61.2, 36.5, 60)
      ..close();
    canvas.drawPath(body, Paint()..color = bodyColor);
    if (!monochrome) {
      canvas.drawPath(
        Path()
          ..moveTo(36.5, 57.5)
          ..lineTo(68.8, 57.5)
          ..lineTo(68.8, 60)
          ..quadraticBezierTo(68.8, 61.2, 67.6, 61.2)
          ..lineTo(37.7, 61.2)
          ..quadraticBezierTo(36.5, 61.2, 36.5, 60)
          ..close(),
        Paint()..color = Brand.amberDeep,
      );
    }

    // Windows (cut out in monochrome).
    final glass = monochrome ? (Paint()..blendMode = BlendMode.clear) : (Paint()..color = Brand.navy);
    {
      canvas.drawPath(
        Path()
          ..moveTo(46.6, 51.2)
          ..lineTo(50.2, 46.8)
          ..lineTo(54.4, 46.8)
          ..lineTo(54.4, 51.2)
          ..close(),
        glass,
      );
      canvas.drawPath(
        Path()
          ..moveTo(56.2, 46.8)
          ..lineTo(59.6, 46.8)
          ..lineTo(62.8, 51.2)
          ..lineTo(56.2, 51.2)
          ..close(),
        glass,
      );
      // Headlight.
      if (!monochrome) canvas.drawCircle(const Offset(67.3, 54.6), 0.9, Paint()..color = Colors.white);
    }

    // Wheels.
    for (final x in [43.2, 62.0]) {
      canvas.drawCircle(Offset(x, 61.4), 3.9, Paint()..color = monochrome ? Colors.white : Brand.navy);
      canvas.drawCircle(
          Offset(x, 61.4), 1.5, monochrome ? (Paint()..blendMode = BlendMode.clear) : (Paint()..color = Colors.white));
    }
    if (monochrome) canvas.restore();
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DriveSyncMarkPainter old) =>
      old.background != background || old.roundedTile != roundedTile || old.monochrome != monochrome || old.glyphScale != glyphScale || old.glyph != glyph;
}

/// The mark as a widget.
class DriveSyncMark extends StatelessWidget {
  const DriveSyncMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: DriveSyncMarkPainter()),
      );
}

/// Mark + "DriveSync" wordmark.
class DriveSyncLogo extends StatelessWidget {
  const DriveSyncLogo({super.key, this.size = 40, this.vertical = false});
  final double size;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final word = Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Drive', style: TextStyle(color: scheme.onSurface)),
        TextSpan(text: 'Sync', style: TextStyle(color: scheme.primary)),
      ]),
      style: TextStyle(fontSize: size * (vertical ? 0.62 : 0.55), fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1),
    );
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [DriveSyncMark(size: size * 1.8), SizedBox(height: size * 0.35), word])
        : Row(mainAxisSize: MainAxisSize.min, children: [DriveSyncMark(size: size), SizedBox(width: size * 0.28), word]);
  }
}
