import 'package:flutter/material.dart';

/// Every colour the app paints comes from here.
///
/// The look follows Samsung's One UI: a soft grey canvas with white rounded
/// cards in light mode, true black with dark-grey cards in dark mode (kind to
/// OLED screens and to eyes at night), one blue accent, and the usual green,
/// orange and red for status.
@immutable
class Tones extends ThemeExtension<Tones> {
  const Tones({
    required this.canvas,
    required this.card,
    required this.cardHigh,
    required this.ink,
    required this.sub,
    required this.faint,
    required this.divider,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.good,
    required this.warn,
    required this.bad,
    required this.warnSoft,
    required this.badSoft,
    required this.glass,
    required this.shadow,
  });

  /// Page background, cards on it, and a raised surface inside a card.
  final Color canvas, card, cardHigh;

  /// Primary text, secondary text, tertiary text and icons.
  final Color ink, sub, faint;

  /// Inset dividers between rows in a card.
  final Color divider;

  /// The one accent: primary buttons, selection, the route line.
  final Color accent, onAccent, accentSoft;

  /// Status: live/ok, attention, problem; soft fills for banners.
  final Color good, warn, bad, warnSoft, badSoft;

  /// Translucent surface for panels floating over the map (blurred behind).
  final Color glass;

  final Color shadow;

  static const light = Tones(
    canvas: Color(0xFFF4F4F6),
    card: Color(0xFFFFFFFF),
    cardHigh: Color(0xFFF0F1F4),
    ink: Color(0xFF111114),
    sub: Color(0xFF6C6D73),
    faint: Color(0xFF9C9DA3),
    divider: Color(0xFFE6E7EA),
    accent: Color(0xFF2F6BFF),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE5EDFF),
    good: Color(0xFF1FA45B),
    warn: Color(0xFFF08A00),
    bad: Color(0xFFE5383B),
    warnSoft: Color(0xFFFFF1DC),
    badSoft: Color(0xFFFDE5E5),
    glass: Color(0xD9FFFFFF),
    shadow: Color(0x1F1B2240),
  );

  static const dark = Tones(
    canvas: Color(0xFF000000),
    card: Color(0xFF17171A),
    cardHigh: Color(0xFF242428),
    ink: Color(0xFFF4F4F6),
    sub: Color(0xFFA0A1A8),
    faint: Color(0xFF6E6F75),
    divider: Color(0xFF2A2A2F),
    accent: Color(0xFF5C8DFF),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFF1B2747),
    good: Color(0xFF3CCB7F),
    warn: Color(0xFFFFA62B),
    bad: Color(0xFFFF5B5E),
    warnSoft: Color(0xFF33260F),
    badSoft: Color(0xFF3A1717),
    glass: Color(0xCC1C1C20),
    shadow: Color(0x66000000),
  );

  /// Colours a member picks for their vehicle, shown on avatars and the map.
  static const vehicleColours = [
    0xFF2F6BFF, 0xFFE5383B, 0xFF1FA45B, 0xFFF08A00, 0xFF8B5CF6, 0xFF0EA5A4, 0xFF4B5563,
  ];

  /// Hex for MapLibre style properties, which take CSS colour strings.
  static String css(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Tones copyWith() => this;

  @override
  Tones lerp(Tones? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Tones(
      canvas: l(canvas, other.canvas),
      card: l(card, other.card),
      cardHigh: l(cardHigh, other.cardHigh),
      ink: l(ink, other.ink),
      sub: l(sub, other.sub),
      faint: l(faint, other.faint),
      divider: l(divider, other.divider),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      good: l(good, other.good),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
      warnSoft: l(warnSoft, other.warnSoft),
      badSoft: l(badSoft, other.badSoft),
      glass: l(glass, other.glass),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Corner radii: generous and consistent, as in One UI.
abstract final class Radii {
  static const card = 26.0;
  static const tile = 20.0;
  static const field = 18.0;
  static const icon = 12.0;
}

extension TonesContext on BuildContext {
  Tones get tones => Theme.of(this).extension<Tones>()!;
}
