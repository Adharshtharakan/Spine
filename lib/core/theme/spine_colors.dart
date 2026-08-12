import 'package:flutter/material.dart';

/// The Spine palette. These are the exact values from the React prototype —
/// they are the visual identity and should not drift.
abstract final class SpineColors {
  /// Page background — near-black warm ink.
  static const ink = Color(0xFF16140F);

  /// Slightly lifted ink used for raised surfaces.
  static const inkCard = Color(0xFF1D1911);

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
    center: Alignment(0, -0.6),
    radius: 1.1,
    colors: [Color(0xFF242016), ink],
  );

  /// Ink at a given opacity — used for text on top of a spine-coloured panel.
  static Color onSpine(double opacity) => ink.withValues(alpha: opacity);

  /// Parchment at a given opacity — used for body copy on ink.
  static Color onInk(double opacity) => parchment.withValues(alpha: opacity);
}
