import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// CupertinoPageTransitionsBuilder, used below. Some Flutter versions
// re-export it through material.dart and flag this import as unnecessary;
// others don't, and removing it breaks the build there. Keep it.
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'spine_palette.dart';
import 'spine_text.dart';

abstract final class SpineTheme {
  /// Builds the theme for one palette.
  ///
  /// The palette rides along as a [ThemeExtension] so every widget can reach
  /// the mode it is being read in through `context.palette`, rather than the
  /// colours being compile-time constants as they were when Spine was dark
  /// only.
  static ThemeData build(SpinePalette palette) {
    final base = palette.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      extensions: [palette],
      brightness: palette.brightness,
      scaffoldBackgroundColor: palette.ground,
      colorScheme: base.colorScheme.copyWith(
        primary: palette.brass,
        surface: palette.ground,
        onSurface: palette.text,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: SpineText.sans,
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: palette.line,
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

  /// The status and navigation bars have to invert with the page, or the
  /// clock and the battery disappear into it.
  static SystemUiOverlayStyle overlayFor(SpinePalette palette) {
    final icons = palette.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS reads the *bar's* brightness, which is the opposite of its icons'.
      statusBarBrightness: palette.brightness,
      systemNavigationBarColor: palette.ground,
      systemNavigationBarIconBrightness: icons,
    );
  }
}
