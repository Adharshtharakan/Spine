import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'spine_colors.dart';
import 'spine_text.dart';

abstract final class SpineTheme {
  /// Spine is a single-mode, dark editorial surface by design — there is no
  /// light theme, the same way a cinema doesn't have one.
  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: SpineColors.ink,
      colorScheme: base.colorScheme.copyWith(
        primary: SpineColors.brass,
        surface: SpineColors.ink,
        onSurface: SpineColors.parchment,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: SpineText.sans,
        bodyColor: SpineColors.parchment,
        displayColor: SpineColors.parchment,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: SpineColors.line,
      // The feed owns the whole screen; a stretch/glow overscroll would fight
      // the snap. Slides get a subtle scale-press instead.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: SpineColors.ink,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
