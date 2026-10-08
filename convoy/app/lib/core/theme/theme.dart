import 'package:flutter/material.dart';

/// High-contrast, large-target theme: the app is glanced at from a mounted
/// phone, so text and buttons are sized for arm's length.
abstract final class ConvoyTheme {
  static const seed = Color(0xFF1F6FEB);
  static const lead = Color(0xFFF5A524);
  static const offline = Color(0xFF8E8E93);
  static const mesh = Color(0xFF7C4DFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    );
  }
}
