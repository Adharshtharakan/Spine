import 'package:flutter/material.dart';

/// Every colour the app paints comes from here (Hallmark Floor 1).
///
/// Theme: Hallmark "Wayfind" — public signage as an interface. Cool grey
/// paper, blue-black ink, square 2 px ink borders, ink plates that carry a
/// sign, cobalt for what is live, amber for figures (only on ink, or as a fill
/// under ink text). Two colourways: `platform` (light) and `night` (dark).
@immutable
class Wayfind extends ThemeExtension<Wayfind> {
  const Wayfind({
    required this.paper,
    required this.paper2,
    required this.paper3,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.rule,
    required this.live,
    required this.onLive,
    required this.figure,
    required this.onFigure,
    required this.plate,
    required this.onPlate,
    required this.plateMuted,
    required this.plateRule,
  });

  /// Page background, raised band, and the lightest well (inputs, rows).
  final Color paper, paper2, paper3;

  /// Text and borders.
  final Color ink, ink2, muted;

  /// Hairline row dividers.
  final Color rule;

  /// Cobalt: what is live — the primary action, the current selection, live state.
  final Color live, onLive;

  /// Amber: figures on a plate, or a fill under ink text (warnings, late rows).
  final Color figure, onFigure;

  /// The sign plate: a square field of ink holding one instruction and its figure.
  final Color plate, onPlate, plateMuted, plateRule;

  static const platform = Wayfind(
    paper: Color(0xFFEDF0F4),
    paper2: Color(0xFFDDE2E7),
    paper3: Color(0xFFFBFEFF),
    ink: Color(0xFF0A0D13),
    ink2: Color(0xFF282B32),
    muted: Color(0xFF565B64),
    rule: Color(0xFFB9BEC5),
    live: Color(0xFF2055E1),
    onLive: Color(0xFFFCFEFF),
    figure: Color(0xFFF4B522),
    onFigure: Color(0xFF0A0D13),
    plate: Color(0xFF0A0D13),
    onPlate: Color(0xFFEDF0F4),
    plateMuted: Color(0xFFA3A9B2),
    plateRule: Color(0xFF34383F),
  );

  static const night = Wayfind(
    paper: Color(0xFF080B10),
    paper2: Color(0xFF13161C),
    paper3: Color(0xFF111419),
    ink: Color(0xFFEFF2F5),
    ink2: Color(0xFFC7CBD0),
    muted: Color(0xFF9399A1),
    rule: Color(0xFF2C3038),
    live: Color(0xFF457CFD),
    onLive: Color(0xFFFCFEFF),
    figure: Color(0xFFF4B522),
    onFigure: Color(0xFF0A0D13),
    // At night a plate stays dark (no glare on a mounted phone) and is told
    // apart from the paper by its border.
    plate: Color(0xFF1A1E25),
    onPlate: Color(0xFFEFF2F5),
    plateMuted: Color(0xFF9399A1),
    plateRule: Color(0xFF3A3F48),
  );

  /// Colours a member picked for their vehicle: the convoy's own "line
  /// colours", shown as small squares beside names and as dots on the map.
  static const vehicleColours = [
    0xFF2055E1, 0xFFD6453D, 0xFF2E9E6A, 0xFFE0A21B, 0xFF7C4DCC, 0xFF14A0A0, 0xFF3A3F48,
  ];

  /// Hex for MapLibre style properties, which take CSS colour strings.
  static String css(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Wayfind copyWith() => this;

  /// Departure-board stiff: colours switch, they never blend (steps(1)).
  @override
  Wayfind lerp(Wayfind? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Square surfaces with a 2 px rule: the theme's one radius and one border.
abstract final class Rules {
  static const bar = 2.0;
  static const hair = 1.0;
  static const square = BorderRadius.zero;
}

extension WayfindContext on BuildContext {
  Wayfind get wf => Theme.of(this).extension<Wayfind>()!;
}
