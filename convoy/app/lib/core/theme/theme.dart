import 'package:flutter/material.dart';

import '../brand/logo.dart';

/// DriveSync's look, light and dark. Large targets and strong contrast: the
/// app is glanced at from a mounted phone, often in bright sun or at night.
abstract final class ConvoyTheme {
  static const seed = Brand.blue;
  static const lead = Brand.amber;
  static const offline = Color(0xFF6B7280);
  static const mesh = Color(0xFF7C4DFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme scheme(Brightness b) {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    if (b == Brightness.light) {
      return base.copyWith(
        primary: Brand.blue,
        onPrimary: Colors.white,
        tertiary: Brand.amberDeep,
        tertiaryContainer: const Color(0xFFFFE7B8),
        onTertiaryContainer: const Color(0xFF3D2700),
        surface: const Color(0xFFF6F8FC),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF1F4FA),
        surfaceContainer: const Color(0xFFEBEFF7),
        surfaceContainerHigh: const Color(0xFFE4E9F3),
        surfaceContainerHighest: const Color(0xFFDDE3EF),
        onSurface: const Color(0xFF111827),
        onSurfaceVariant: const Color(0xFF4B5563),
        outlineVariant: const Color(0xFFD6DCE8),
      );
    }
    return base.copyWith(
      primary: const Color(0xFF7DB1FF),
      onPrimary: const Color(0xFF032558),
      primaryContainer: const Color(0xFF173A73),
      onPrimaryContainer: const Color(0xFFD7E5FF),
      tertiary: Brand.amber,
      tertiaryContainer: const Color(0xFF4A3300),
      onTertiaryContainer: const Color(0xFFFFDDA0),
      surface: const Color(0xFF0D121C),
      surfaceContainerLowest: const Color(0xFF090D15),
      surfaceContainerLow: const Color(0xFF131A27),
      surfaceContainer: const Color(0xFF172030),
      surfaceContainerHigh: const Color(0xFF1D2739),
      surfaceContainerHighest: const Color(0xFF243044),
      onSurface: const Color(0xFFE7ECF5),
      onSurfaceVariant: const Color(0xFFA6B0C2),
      outlineVariant: const Color(0xFF2B3548),
    );
  }

  static ThemeData _build(Brightness b) {
    final s = scheme(b);
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final base = ThemeData(colorScheme: s, useMaterial3: true, brightness: b);
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: s.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: s.onSurface, fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: s.outlineVariant.withValues(alpha: b == Brightness.light ? 0.7 : 1)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: rounded,
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded, side: BorderSide(color: s.outlineVariant)),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: rounded)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHigh.withValues(alpha: b == Brightness.light ? 0.6 : 1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: s.primary, width: 2)),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: s.outlineVariant),
        backgroundColor: s.surfaceContainerLow,
        selectedColor: s.primaryContainer,
        labelStyle: text.labelLarge?.copyWith(color: s.onSurface, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primary.withValues(alpha: b == Brightness.light ? 0.14 : 0.24),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelMedium?.copyWith(
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              color: states.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant)),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 10,
        iconColor: s.onSurfaceVariant,
        titleTextStyle: text.titleMedium?.copyWith(color: s.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: s.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: s.outlineVariant.withValues(alpha: 0.6), space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge?.copyWith(color: s.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(selectedBackgroundColor: s.primaryContainer, shape: rounded),
      ),
    );
  }
}
