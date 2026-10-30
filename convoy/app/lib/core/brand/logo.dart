import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// DriveSync brand colours: the mark is a sign plate in the Wayfind palette.
abstract final class Brand {
  static final plate = Wayfind.platform.plate;
  static final paper = Wayfind.platform.paper;
  static final amber = Wayfind.platform.figure;
}

/// The DriveSync mark: a sign plate (flat ink, square) carrying a bold "D"
/// with a car in its curve. Drawn in code so the in-app logo and every
/// launcher icon (generated from this painter by `tool/gen_icons_test.dart`)
/// are identical and stay crisp at any size. No gradient, no gloss.
class DriveSyncMarkPainter extends CustomPainter {
  const DriveSyncMarkPainter({
    this.background = true,
    this.roundedTile = false,
    this.monochrome = false,
    this.glyphScale = 1.0,
    this.glyph = true,
  });

  /// Paint the D-and-car glyph (off for an adaptive icon's background layer).
  final bool glyph;

  /// Paint the ink plate behind the glyph.
  final bool background;

  /// Slightly round the plate's corners like a pressed sign (legacy Android
  /// launcher icons only; in the app and on iOS the plate is square).
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
      final paint = Paint()..color = Brand.plate;
      if (roundedTile) {
        canvas.drawRRect(RRect.fromRectAndRadius(tile, Radius.circular(s * 0.1)), paint);
      } else {
        canvas.drawRect(tile, paint);
      }
    }

    if (!glyph) {
      canvas.restore();
      return;
    }

    // Glyph in a 100×100 design space.
    canvas.translate(s / 2, s / 2);
    canvas.scale(s / 100 * glyphScale);
    canvas.translate(-50, -50);

    final paper = Paint()..color = monochrome ? Colors.white : Brand.paper;

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
    canvas.drawPath(d, paper);

    // The car sits in the D's counter, slightly smaller than the opening.
    canvas.save();
    canvas.translate(52, 54);
    canvas.scale(0.88);
    canvas.translate(-52, -54);
    // Monochrome: draw on a layer so windows and hubs can be cut out.
    if (monochrome) canvas.saveLayer(null, Paint());

    // Road line the car drives on.
    final road = Paint()
      ..color = paper.color
      ..strokeWidth = 1.6;
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

    // Windows (cut out in monochrome).
    final glass = monochrome ? (Paint()..blendMode = BlendMode.clear) : (Paint()..color = Brand.plate);
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
      if (!monochrome) canvas.drawRect(const Rect.fromLTWH(66.6, 53.8, 1.6, 1.6), Paint()..color = Brand.paper);
    }

    // Wheels.
    for (final x in [43.2, 62.0]) {
      canvas.drawCircle(Offset(x, 61.4), 3.9, Paint()..color = monochrome ? Colors.white : Brand.paper);
      canvas.drawCircle(
          Offset(x, 61.4), 1.6, monochrome ? (Paint()..blendMode = BlendMode.clear) : (Paint()..color = Brand.plate));
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

/// Mark + "DriveSync" wordmark, one ink colour.
class DriveSyncLogo extends StatelessWidget {
  const DriveSyncLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final word = Text(
      'DriveSync',
      style: TextStyle(
        fontSize: size * 0.56,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.03 * size * 0.56,
        height: 1,
        color: context.wf.ink,
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [DriveSyncMark(size: size), SizedBox(width: size * 0.3), word]);
  }
}
