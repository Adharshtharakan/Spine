import 'package:flutter/material.dart';

/// The Spine palette. These are the exact values from the React prototype —
/// they are the visual identity and should not drift.
abstract final class SpineColors {
  /// Page background — near-black, faintly warm. Deep enough that a coloured
  /// bloom on top of it reads as light rather than paint.
  static const ink = Color(0xFF0D0C09);

  /// Slightly lifted ink used for raised surfaces.
  static const inkCard = Color(0xFF171510);

  /// Filled control surfaces, in place of outlines. Spine draws almost no
  /// borders: a control is a plane at a different height, not a rectangle with
  /// a line around it.
  static const surface = Color(0x0FF1E9D6);
  static const surfaceRaised = Color(0x1AF1E9D6);
  static const surfacePressed = Color(0x24F1E9D6);

  /// Primary reading colour — warm off-white, like aged paper.
  static const parchment = Color(0xFFF1E9D6);

  /// Secondary/label colour.
  static const parchmentDim = Color(0xFFB7AC90);

  /// Accent — brass foil.
  static const brass = Color(0xFFC9A227);
  static const brassDim = Color(0xFF7A6A2F);

  /// Spine colours available to books.
  static const teal = Color(0xFF3E7068);
  static const brick = Color(0xFFB1543F);
  static const indigo = Color(0xFF4A4E7C);
  static const olive = Color(0xFF6B7A3D);

  /// Hairline divider — parchment at 14%.
  static const line = Color(0x24F1E9D6);

  /// Named spine colours, addressable from content JSON so book data never has
  /// to hard-code a hex value (though it may).
  static const spinePalette = <String, Color>{
    'brass': brass,
    'teal': teal,
    'brick': brick,
    'indigo': indigo,
    'olive': olive,
  };

  /// Resolves a `spine` field from content: either a palette name (`"brass"`)
  /// or a hex string (`"#C9A227"` / `"C9A227"` / `"#FFC9A227"`).
  static Color resolveSpine(String value, {Color fallback = brass}) {
    final named = spinePalette[value.trim().toLowerCase()];
    if (named != null) return named;

    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  /// The ambient background wash behind the feed.
  static const feedBackground = RadialGradient(
    center: Alignment(0, -0.75),
    radius: 1.2,
    colors: [Color(0xFF17150F), ink],
  );

  /// The out-of-focus light field behind a book — the book's colour arriving as
  /// atmosphere rather than as a panel. Stops are deliberately soft and never
  /// reach full saturation.
  static List<Color> bloomFor(Color spine) => [
    spine.withValues(alpha: 0.55),
    spine.withValues(alpha: 0.22),
    spine.withValues(alpha: 0.06),
    Colors.transparent,
  ];

  static const bloomStops = [0.0, 0.38, 0.68, 1.0];

  /// Ink at a given opacity — used for text on top of a spine-coloured panel.
  static Color onSpine(double opacity) => ink.withValues(alpha: opacity);

  /// Parchment at a given opacity — used for body copy on ink.
  static Color onInk(double opacity) => parchment.withValues(alpha: opacity);
}
