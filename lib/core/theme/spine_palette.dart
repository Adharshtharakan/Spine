import 'package:flutter/material.dart';

import 'spine_colors.dart';

/// The palette, in the mode currently being read.
///
/// Spine used to be a single dark surface, so its colours were compile-time
/// constants. With two modes they have to resolve per build, which is why this
/// is a [ThemeExtension] read from context rather than a set of statics.
///
/// The roles are named for what they *do*, not what they look like: `ground` is
/// the page, `text` is what is written on it. Light mode is not the dark one
/// inverted — paper is warm and near-white, ink is near-black, and the brass
/// has to darken to hold contrast against cream.
@immutable
class SpinePalette extends ThemeExtension<SpinePalette> {
  const SpinePalette({
    required this.brightness,
    required this.ground,
    required this.groundRaised,
    required this.surface,
    required this.surfaceRaised,
    required this.surfacePressed,
    required this.text,
    required this.textDim,
    required this.line,
    required this.brass,
    required this.brassDim,
    required this.ribbon,
    required this.ribbonEdge,
  });

  final Brightness brightness;

  /// The page itself.
  final Color ground;

  /// A plane lifted off the page — sheets, cards, the nav bar.
  final Color groundRaised;

  /// Filled control surfaces. Spine draws almost no borders: a control is a
  /// plane at a different height, not a rectangle with a line around it.
  final Color surface;
  final Color surfaceRaised;
  final Color surfacePressed;

  /// What is written on the ground.
  final Color text;
  final Color textDim;

  final Color line;

  /// Accent. Brass foil on dark, a deeper bronze on paper — the dark-mode value
  /// is too pale to read against cream.
  final Color brass;
  final Color brassDim;

  /// The bookmark ribbon's own body and its stitched edge.
  final Color ribbon;
  final Color ribbonEdge;

  /// The field behind every tab. A faint lift toward the top rather than a flat
  /// fill, so a screen of plain text still has somewhere to look. This used to
  /// be a hardcoded dark gradient in the shell, which left Search, Saved and
  /// Profile dark on paper — the shelf was only ever hiding it behind a card.
  Gradient get backdrop => RadialGradient(
    center: const Alignment(0, -0.75),
    radius: 1.2,
    colors: [groundRaised, ground],
  );

  bool get isDark => brightness == Brightness.dark;

  /// Text at a given strength, for the many places that want a softer weight
  /// of the reading colour rather than a separate hue.
  Color onGround(double opacity) => text.withValues(alpha: opacity);

  /// A book's spine colour, adjusted to stay legible on this ground.
  ///
  /// The catalogue's colours were chosen against near-black. On paper the
  /// lighter ones — brass especially — lose almost all contrast, so they are
  /// darkened rather than shown as-is.
  Color accent(Color spineColour) {
    if (isDark) return spineColour;
    final hsl = HSLColor.fromColor(spineColour);
    return hsl
        .withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
        .toColor();
  }

  static const dark = SpinePalette(
    brightness: Brightness.dark,
    ground: Color(0xFF0D0C09),
    groundRaised: Color(0xFF171510),
    surface: Color(0x0FF1E9D6),
    surfaceRaised: Color(0x1AF1E9D6),
    surfacePressed: Color(0x24F1E9D6),
    text: Color(0xFFF1E9D6),
    textDim: Color(0xFFB7AC90),
    line: Color(0x24F1E9D6),
    brass: SpineColors.brass,
    brassDim: SpineColors.brassDim,
    ribbon: Color(0xFF8A6E2F),
    ribbonEdge: Color(0xFF6B5423),
  );

  /// Paper. Warm off-white rather than pure white — a book page, and easier to
  /// hold for the length of a reading session.
  static const light = SpinePalette(
    brightness: Brightness.light,
    ground: Color(0xFFF7F3EC),
    groundRaised: Color(0xFFFFFDF8),
    surface: Color(0x0F1A1710),
    surfaceRaised: Color(0xFFFFFDF8),
    surfacePressed: Color(0x1A1A1710),
    text: Color(0xFF17140E),
    textDim: Color(0xFF6E6656),
    line: Color(0x1A1A1710),
    brass: Color(0xFFA9761C),
    brassDim: Color(0xFFC49A4A),
    ribbon: Color(0xFFD9B978),
    ribbonEdge: Color(0xFFB08E4E),
  );

  @override
  SpinePalette copyWith({
    Brightness? brightness,
    Color? ground,
    Color? groundRaised,
    Color? surface,
    Color? surfaceRaised,
    Color? surfacePressed,
    Color? text,
    Color? textDim,
    Color? line,
    Color? brass,
    Color? brassDim,
    Color? ribbon,
    Color? ribbonEdge,
  }) {
    return SpinePalette(
      brightness: brightness ?? this.brightness,
      ground: ground ?? this.ground,
      groundRaised: groundRaised ?? this.groundRaised,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      line: line ?? this.line,
      brass: brass ?? this.brass,
      brassDim: brassDim ?? this.brassDim,
      ribbon: ribbon ?? this.ribbon,
      ribbonEdge: ribbonEdge ?? this.ribbonEdge,
    );
  }

  @override
  SpinePalette lerp(ThemeExtension<SpinePalette>? other, double t) {
    if (other is! SpinePalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return SpinePalette(
      // Brightness is a switch, not a scale — it flips at the halfway point so
      // status-bar icons never sit mid-cross-fade in an unreadable state.
      brightness: t < 0.5 ? brightness : other.brightness,
      ground: mix(ground, other.ground),
      groundRaised: mix(groundRaised, other.groundRaised),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfacePressed: mix(surfacePressed, other.surfacePressed),
      text: mix(text, other.text),
      textDim: mix(textDim, other.textDim),
      line: mix(line, other.line),
      brass: mix(brass, other.brass),
      brassDim: mix(brassDim, other.brassDim),
      ribbon: mix(ribbon, other.ribbon),
      ribbonEdge: mix(ribbonEdge, other.ribbonEdge),
    );
  }
}

extension SpinePaletteContext on BuildContext {
  /// The palette for the mode being read. Falls back to dark so a widget built
  /// outside the app's theme — a preview, a test harness — still renders.
  SpinePalette get palette =>
      Theme.of(this).extension<SpinePalette>() ?? SpinePalette.dark;
}
