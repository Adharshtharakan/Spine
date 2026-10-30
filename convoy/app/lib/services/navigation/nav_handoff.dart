import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo/geo.dart';

/// Turn-by-turn is best left to a navigation app; DriveSync keeps tracking
/// the convoy in the background while it runs.
enum NavApp {
  googleMaps,
  osmAnd,
  waze,
  appleMaps;

  String get label => switch (this) {
        NavApp.googleMaps => 'Google Maps',
        NavApp.osmAnd => 'OsmAnd (works offline)',
        NavApp.waze => 'Waze',
        NavApp.appleMaps => 'Apple Maps',
      };

  static List<NavApp> get forPlatform =>
      Platform.isIOS ? [NavApp.appleMaps, NavApp.googleMaps, NavApp.waze, NavApp.osmAnd] : [NavApp.googleMaps, NavApp.osmAnd, NavApp.waze];
}

abstract final class NavHandoff {
  static const _prefKey = 'nav_app';

  /// The app-specific link that starts driving directions to [to].
  static Uri uri(NavApp app, GeoPoint to, {String? name, bool android = true}) {
    final ll = '${to.lat.toStringAsFixed(6)},${to.lng.toStringAsFixed(6)}';
    return switch (app) {
      NavApp.googleMaps => android
          ? Uri.parse('google.navigation:q=$ll&mode=d')
          : Uri.parse('comgooglemaps://?daddr=$ll&directionsmode=driving'),
      NavApp.osmAnd => Uri(scheme: 'osmand.api', host: 'navigate', queryParameters: {
          'dest_lat': to.lat.toStringAsFixed(6),
          'dest_lon': to.lng.toStringAsFixed(6),
          'dest_name': ?name,
          'profile': 'car',
          'force': 'true',
        }),
      NavApp.waze => Uri.parse('https://waze.com/ul?ll=$ll&navigate=yes'),
      NavApp.appleMaps => Uri.parse('https://maps.apple.com/?daddr=$ll&dirflg=d'),
    };
  }

  /// Web fallback that works everywhere a browser does.
  static Uri webFallback(GeoPoint to) => Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${to.lat.toStringAsFixed(6)},${to.lng.toStringAsFixed(6)}&travelmode=driving');

  static Future<NavApp?> preferred() async {
    final p = await SharedPreferences.getInstance();
    return NavApp.values.where((a) => a.name == p.getString(_prefKey)).firstOrNull;
  }

  static Future<void> setPreferred(NavApp app) async =>
      (await SharedPreferences.getInstance()).setString(_prefKey, app.name);

  /// Opens [app] (or the web fallback if it is not installed).
  static Future<bool> start(NavApp app, GeoPoint to, {String? name}) async {
    final u = uri(app, to, name: name, android: Platform.isAndroid);
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // Not installed: fall through.
    }
    return launchUrl(webFallback(to), mode: LaunchMode.externalApplication);
  }
}
