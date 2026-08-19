import 'package:flutter/material.dart';

import '../../data/models/book.dart';
import 'ambient_backdrop.dart';

/// The book's cover art, filling the card behind everything else.
///
/// The art is composed to carry its weight in the upper two thirds and fall to
/// ink below, because that's where the idea's text sits — so the card needs no
/// scrim heavy enough to grey the art out. See `tool/generate_covers.py`.
///
/// Falls back to [AmbientBackdrop] for any book without cover art, which is
/// what the whole shelf looked like before covers existed.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({
    super.key,
    required this.book,
    this.parallax = 0,
    this.intensity = 1,
  });

  final Book book;

  /// -1..1 — how far this card is from resting. The art drifts slower than the
  /// card, which is what sells depth while swiping.
  final double parallax;

  /// 0..1 — dims neighbouring cards.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final asset = _assetPath(book.coverUrl);
    if (asset == null) {
      return AmbientBackdrop(
        color: book.spineColor,
        parallax: parallax,
        intensity: intensity,
      );
    }

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Overscaled so the parallax shift never exposes an edge.
            Transform.translate(
              offset: Offset(0, parallax * 42),
              child: Transform.scale(
                scale: 1.12,
                child: Opacity(
                  opacity: intensity.clamp(0.0, 1.0),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (context, error, stack) => AmbientBackdrop(
                      color: book.spineColor,
                      intensity: intensity,
                    ),
                  ),
                ),
              ),
            ),
            // Only the top band is veiled, for the masthead. The art's own
            // fade already handles the bottom.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x730D0C09), Color(0x000D0C09)],
                  stops: [0, 0.22],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Catalogue refs are `asset:` or `https:`; only bundled art is supported
  /// here, and a remote cover falls back rather than blocking the card on a
  /// network fetch.
  static String? _assetPath(String? ref) {
    if (ref == null || !ref.startsWith('asset:')) return null;
    return ref.substring('asset:'.length);
  }
}
