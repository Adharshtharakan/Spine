import 'ad_config.dart';

/// Build-time configuration. Everything here can be overridden with
/// `--dart-define`, so flavours (dev / staging / store) need no code change:
///
/// ```
/// flutter run --dart-define=SPINE_AD_FREQUENCY=5 --dart-define=SPINE_ADS=false
/// ```
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.contentManifest,
    required this.contentBaseUrl,
    required this.ads,
  });

  /// `dev` | `staging` | `prod`.
  final String environment;

  /// Asset path of the bundled catalogue. Swapping this for a network fetch is
  /// a repository change only — nothing above the repository knows the source.
  final String contentManifest;

  /// Base URL for cloud-hosted content (audio, covers) once it exists. Empty
  /// means "everything ships in the bundle", which is the MVP.
  final String contentBaseUrl;

  final AdConfig ads;

  bool get isProd => environment == 'prod';

  static AppConfig fromEnvironment() {
    return AppConfig(
      environment: const String.fromEnvironment(
        'SPINE_ENV',
        defaultValue: 'dev',
      ),
      contentManifest: const String.fromEnvironment(
        'SPINE_CONTENT',
        defaultValue: 'assets/content/books.json',
      ),
      contentBaseUrl: const String.fromEnvironment('SPINE_CONTENT_BASE_URL'),
      ads: AdConfig.fromEnvironment(),
    );
  }
}
