import 'package:flutter/material.dart';

import 'tokens.dart';

/// DriveSync's look: Hallmark's Wayfind theme applied to app screens.
///
/// Signage you read at a glance from a mounted phone: one face (Chivo Mono,
/// a grotesk cut to a departure board's fixed cell), square surfaces with
/// 2 px ink rules, cobalt only for what is live, amber only for figures.
/// Type scale fixed at a ratio of about 1.2; motion is a state change, never
/// decoration.
abstract final class ConvoyTheme {
  static const fontFamily = 'ChivoMono';

  static ThemeData light() => _build(Brightness.light, Wayfind.platform);
  static ThemeData dark() => _build(Brightness.dark, Wayfind.night);

  static TextTheme _text(Wayfind w) {
    TextStyle s(double size, FontWeight weight, {double height = 1.4, Color? color}) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: weight == FontWeight.w800 ? -0.03 * size : 0,
          color: color ?? w.ink,
        );
    const heavy = FontWeight.w800, mid = FontWeight.w500, regular = FontWeight.w400;
    return TextTheme(
      displayLarge: s(52, heavy, height: 0.98),
      displayMedium: s(44, heavy, height: 0.98),
      displaySmall: s(36, heavy, height: 1.0),
      headlineLarge: s(31, heavy, height: 1.02),
      headlineMedium: s(26, heavy, height: 1.05),
      headlineSmall: s(22, heavy, height: 1.1),
      titleLarge: s(19, heavy, height: 1.15),
      titleMedium: s(16, heavy, height: 1.25),
      titleSmall: s(14, mid, height: 1.3),
      bodyLarge: s(16, regular, height: 1.55),
      bodyMedium: s(14, regular, height: 1.5),
      bodySmall: s(12.5, regular, height: 1.45, color: w.muted),
      labelLarge: s(14, heavy, height: 1.1),
      labelMedium: s(12.5, mid, height: 1.2, color: w.muted),
      labelSmall: s(11.5, mid, height: 1.2, color: w.muted),
    );
  }

  static ThemeData _build(Brightness b, Wayfind w) {
    final text = _text(w);
    final scheme = ColorScheme(
      brightness: b,
      primary: w.live,
      onPrimary: w.onLive,
      primaryContainer: w.paper2,
      onPrimaryContainer: w.ink,
      secondary: w.ink,
      onSecondary: w.paper,
      secondaryContainer: w.paper2,
      onSecondaryContainer: w.ink,
      tertiary: w.figure,
      onTertiary: w.onFigure,
      tertiaryContainer: w.figure,
      onTertiaryContainer: w.onFigure,
      // No third bright colour: problems are amber notes under ink text.
      error: w.ink,
      onError: w.paper,
      errorContainer: w.figure,
      onErrorContainer: w.onFigure,
      surface: w.paper,
      onSurface: w.ink,
      onSurfaceVariant: w.muted,
      surfaceContainerLowest: w.paper3,
      surfaceContainerLow: w.paper3,
      surfaceContainer: w.paper2,
      surfaceContainerHigh: w.paper2,
      surfaceContainerHighest: w.paper2,
      outline: w.ink,
      outlineVariant: w.rule,
      inverseSurface: w.plate,
      onInverseSurface: w.onPlate,
      inversePrimary: w.live,
      shadow: w.ink,
      scrim: w.ink,
      surfaceTint: Colors.transparent,
    );
    const square = RoundedRectangleBorder(borderRadius: Rules.square);
    final barSide = BorderSide(color: w.ink, width: Rules.bar);
    final squareBar = RoundedRectangleBorder(borderRadius: Rules.square, side: barSide);
    WidgetStateProperty<T> states<T>(T selected, T other) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? selected : other);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [w],
      scaffoldBackgroundColor: w.paper,
      canvasColor: w.paper,
      visualDensity: VisualDensity.standard,
      // Stiff, like a departure board: no ink ripples, a flat pressed state.
      splashFactory: NoSplash.splashFactory,
      highlightColor: w.paper2,
      hoverColor: w.paper2,
      focusColor: w.live.withValues(alpha: 0.25),
      dividerTheme: DividerThemeData(color: w.rule, thickness: Rules.hair, space: Rules.hair),
      appBarTheme: AppBarTheme(
        backgroundColor: w.paper,
        foregroundColor: w.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        shape: Border(bottom: barSide),
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: w.ink),
      ),
      cardTheme: CardThemeData(
        color: w.paper3,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: squareBar,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: w.live,
          foregroundColor: w.onLive,
          disabledBackgroundColor: w.paper2,
          disabledForegroundColor: w.muted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: square,
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: w.ink,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: square,
          side: barSide,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: w.ink,
          shape: square,
          textStyle: text.labelLarge?.copyWith(decoration: TextDecoration.underline, decorationThickness: 1.5),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: w.ink, shape: square)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: w.live,
        foregroundColor: w.onLive,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: square,
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: w.paper3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        labelStyle: text.bodyMedium?.copyWith(color: w.muted),
        floatingLabelStyle: text.labelMedium?.copyWith(color: w.ink),
        hintStyle: text.bodyMedium?.copyWith(color: w.muted),
        border: OutlineInputBorder(borderRadius: Rules.square, borderSide: barSide),
        enabledBorder: OutlineInputBorder(borderRadius: Rules.square, borderSide: barSide),
        focusedBorder: OutlineInputBorder(
            borderRadius: Rules.square, borderSide: BorderSide(color: w.live, width: Rules.bar + 1)),
        disabledBorder: OutlineInputBorder(borderRadius: Rules.square, borderSide: BorderSide(color: w.rule, width: Rules.bar)),
      ),
      chipTheme: ChipThemeData(
        shape: squareBar,
        side: barSide,
        backgroundColor: w.paper3,
        selectedColor: w.ink,
        checkmarkColor: w.paper,
        labelStyle: text.titleSmall?.copyWith(
            color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? w.paper : w.ink)),
        secondaryLabelStyle: text.titleSmall?.copyWith(color: w.paper),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: w.paper,
        surfaceTintColor: Colors.transparent,
        indicatorColor: w.ink,
        indicatorShape: square,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
              color: w.ink,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            )),
        iconTheme: states(IconThemeData(color: w.paper, size: 22), IconThemeData(color: w.ink2, size: 22)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: w.ink,
        textColor: w.ink,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: w.muted),
        minVerticalPadding: 12,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: w.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: squareBar,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: w.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: Border(top: barSide),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: w.paper3,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: squareBar,
        textStyle: text.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: w.plate,
        contentTextStyle: text.bodyMedium?.copyWith(color: w.onPlate),
        actionTextColor: w.figure,
        shape: RoundedRectangleBorder(borderRadius: Rules.square, side: BorderSide(color: w.plateRule, width: Rules.bar)),
        elevation: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Rules.square),
        side: barSide,
        fillColor: states(w.ink, Colors.transparent),
        checkColor: WidgetStatePropertyAll(w.paper),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: states(w.onLive, w.ink),
        trackColor: states(w.live, w.paper3),
        trackOutlineColor: WidgetStatePropertyAll(w.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(Rules.bar),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(square),
          side: WidgetStatePropertyAll(barSide),
          backgroundColor: states(w.ink, w.paper3),
          foregroundColor: states(w.paper, w.ink),
          iconColor: states(w.paper, w.ink),
          textStyle: WidgetStatePropertyAll(text.titleSmall),
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: w.live, linearTrackColor: w.paper2),
      badgeTheme: BadgeThemeData(backgroundColor: w.live, textColor: w.onLive),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: w.plate, borderRadius: Rules.square),
        textStyle: text.labelMedium?.copyWith(color: w.onPlate),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: w.live, selectionColor: w.figure, selectionHandleColor: w.live),
    );
  }
}
