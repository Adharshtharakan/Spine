import 'package:flutter/material.dart';

import 'tokens.dart';

/// DriveSync's look, modelled on Samsung One UI: large titles, rounded
/// grouped cards on a soft canvas, pill-shaped controls and one blue accent.
/// Text uses the platform face (Roboto on Android, San Francisco on iOS)
/// unless [fontFamily] names another.
abstract final class ConvoyTheme {
  static ThemeData light({String? fontFamily}) => _build(Brightness.light, Tones.light, fontFamily);
  static ThemeData dark({String? fontFamily}) => _build(Brightness.dark, Tones.dark, fontFamily);

  static TextTheme _text(Tones c, String? family) {
    TextStyle s(double size, FontWeight weight, {double height = 1.3, Color? color, double spacing = 0}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? c.ink);
    const bold = FontWeight.w700, semi = FontWeight.w600, mid = FontWeight.w500, regular = FontWeight.w400;
    return TextTheme(
      displayLarge: s(48, bold, height: 1.05, spacing: -0.8),
      displayMedium: s(40, bold, height: 1.08, spacing: -0.6),
      displaySmall: s(34, bold, height: 1.12, spacing: -0.4),
      headlineLarge: s(30, bold, height: 1.15, spacing: -0.3),
      headlineMedium: s(26, bold, height: 1.2, spacing: -0.2),
      headlineSmall: s(22, bold, height: 1.25),
      titleLarge: s(20, bold, height: 1.25),
      titleMedium: s(17, semi, height: 1.3),
      titleSmall: s(15, semi, height: 1.3),
      bodyLarge: s(16, regular, height: 1.45),
      bodyMedium: s(14.5, regular, height: 1.45),
      bodySmall: s(13, regular, height: 1.4, color: c.sub),
      labelLarge: s(15, semi, height: 1.2),
      labelMedium: s(13, mid, height: 1.2, color: c.sub),
      labelSmall: s(11.5, mid, height: 1.2, color: c.sub),
    );
  }

  static ThemeData _build(Brightness b, Tones c, String? fontFamily) {
    final text = _text(c, fontFamily);
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: c.accent,
      tertiary: c.warn,
      onTertiary: Colors.white,
      tertiaryContainer: c.warnSoft,
      onTertiaryContainer: c.ink,
      error: c.bad,
      onError: Colors.white,
      errorContainer: c.badSoft,
      onErrorContainer: c.bad,
      surface: c.canvas,
      onSurface: c.ink,
      onSurfaceVariant: c.sub,
      surfaceContainerLowest: c.card,
      surfaceContainerLow: c.card,
      surfaceContainer: c.card,
      surfaceContainerHigh: c.cardHigh,
      surfaceContainerHighest: c.cardHigh,
      outline: c.faint,
      outlineVariant: c.divider,
      inverseSurface: c.ink,
      onInverseSurface: c.canvas,
      inversePrimary: c.accent,
      shadow: c.shadow,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    const pill = StadiumBorder();
    RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    WidgetStateProperty<T> states<T>(T selected, T other) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? selected : other);
    OutlineInputBorder field([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.field), borderSide: side);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: fontFamily,
      colorScheme: scheme,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [c],
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.ink),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: rounded(Radii.card),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.cardHigh,
          disabledForegroundColor: c.faint,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: pill,
          elevation: 0,
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        // Secondary actions are tonal pills rather than outlines.
        style: OutlinedButton.styleFrom(
          backgroundColor: c.accentSoft,
          foregroundColor: c.accent,
          disabledForegroundColor: c.faint,
          side: BorderSide.none,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.accent, shape: pill, textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 2,
        highlightElevation: 4,
        shape: pill,
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        labelStyle: text.bodyLarge?.copyWith(color: c.sub),
        floatingLabelStyle: text.labelMedium?.copyWith(color: c.accent),
        hintStyle: text.bodyLarge?.copyWith(color: c.faint),
        helperStyle: text.bodySmall,
        border: field(),
        enabledBorder: field(),
        disabledBorder: field(),
        focusedBorder: field(BorderSide(color: c.accent, width: 1.6)),
        errorBorder: field(BorderSide(color: c.bad, width: 1.4)),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide.none,
        backgroundColor: c.card,
        selectedColor: c.accent,
        checkmarkColor: c.onAccent,
        labelStyle: text.titleSmall?.copyWith(
            color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.sub,
        textColor: c.ink,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 12,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: rounded(28),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: c.faint,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: c.shadow,
        shape: rounded(22),
        textStyle: text.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.canvas),
        actionTextColor: c.accent,
        shape: rounded(20),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: c.faint, width: 1.6),
        fillColor: states(c.accent, Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: states(c.accent, c.faint.withValues(alpha: 0.5)),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(BorderSide(color: c.divider)),
          backgroundColor: states(c.accent, c.card),
          foregroundColor: states(c.onAccent, c.ink),
          iconColor: states(c.onAccent, c.sub),
          textStyle: WidgetStatePropertyAll(text.titleSmall),
          minimumSize: const WidgetStatePropertyAll(Size(64, 46)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.cardHigh),
      badgeTheme: BadgeThemeData(backgroundColor: c.bad, textColor: Colors.white),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelMedium?.copyWith(color: c.canvas),
      ),
      textSelectionTheme: TextSelectionThemeData(
          cursorColor: c.accent, selectionColor: c.accent.withValues(alpha: 0.3), selectionHandleColor: c.accent),
    );
  }
}
