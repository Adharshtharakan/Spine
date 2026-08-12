import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';

/// The book's colour as light rather than as a panel.
///
/// This replaces the prototype's gradient cover block. A large, heavily blurred
/// field of the spine colour sits behind the top of the card and falls away to
/// ink, so each book changes the mood of the whole screen instead of stamping a
/// coloured rectangle onto it.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.color,
    this.parallax = 0,
    this.intensity = 1,
  });

  final Color color;

  /// -1..1 — how far this card is from resting position. The light drifts
  /// slower than the card, which is what sells the depth while swiping.
  final double parallax;

  /// 0..1 — fades the whole field, used to dim neighbouring cards.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bloom = size.width * 1.45;

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              // Sits mostly above the top edge: the card catches the edge of a
              // light source rather than containing it.
              top: -bloom * 0.46 + parallax * 60,
              left: -bloom * 0.16,
              width: bloom,
              height: bloom,
              child: Opacity(
                opacity: intensity.clamp(0.0, 1.0),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: SpineColors.bloomFor(color),
                        stops: SpineColors.bloomStops,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // A second, tighter core keeps the centre from washing out flat.
            Positioned(
              top: -bloom * 0.30 + parallax * 34,
              left: size.width * 0.22,
              width: bloom * 0.52,
              height: bloom * 0.52,
              child: Opacity(
                opacity: (intensity * 0.7).clamp(0.0, 1.0),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 56, sigmaY: 56),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: 0.5),
                          color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Settles the lower half back to ink so body copy keeps its
            // contrast no matter how bright the book's colour is.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SpineColors.ink.withValues(alpha: 0),
                      SpineColors.ink.withValues(alpha: 0.55),
                      SpineColors.ink.withValues(alpha: 0.92),
                    ],
                    stops: const [0.18, 0.44, 0.72],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
