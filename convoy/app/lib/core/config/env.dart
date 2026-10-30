/// Build-time configuration, injected with `--dart-define-from-file=env.json`
/// (see `env.example.json`). Nothing secret lives in the app: the Supabase
/// anon key is public by design and every table is protected by RLS.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Cloudflare Worker base URL — tiles, routing, discovery, affiliates,
  /// billing. Empty until the Worker is deployed; the app still runs.
  static const edgeBaseUrl = String.fromEnvironment('EDGE_BASE_URL');
  static bool get hasEdge => edgeBaseUrl.isNotEmpty;

  /// Base for invite links (`<base>/j/CODE`); defaults to the Worker, which
  /// serves the landing page and the Android/iOS app-link files.
  static const _inviteBase = String.fromEnvironment('INVITE_BASE_URL');
  static String get inviteBaseUrl => _inviteBase.isNotEmpty ? _inviteBase : edgeBaseUrl;

  /// Firebase (push notifications). Optional: without these the app works
  /// and simply doesn't receive pushes while closed.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool get hasFirebase => firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseProjectId.isNotEmpty;

  /// Set to true once the self-hosted PMTiles basemap is in R2.
  static const selfHostedTiles = bool.fromEnvironment('SELF_HOSTED_TILES');

  /// Free, key-less OpenStreetMap vector tiles (openfreemap.org): lets the
  /// app run before any map infrastructure exists.
  static const openFreeMapStyle = 'https://tiles.openfreemap.org/styles/liberty';
  static const openFreeMapDarkStyle = 'https://tiles.openfreemap.org/styles/dark';

  /// Map style: explicit override → self-hosted Protomaps via the Worker →
  /// OpenFreeMap.
  static String get mapStyleUrl {
    const override = String.fromEnvironment('MAP_STYLE_URL');
    if (override.isNotEmpty) return override;
    if (hasEdge && selfHostedTiles) return '$edgeBaseUrl/style.json';
    return openFreeMapStyle;
  }

  /// Style for the app's current brightness: our Worker's `?theme=dark`
  /// variant, OpenFreeMap's dark style, or the override as given.
  static String mapStyleUrlFor({required bool dark}) {
    const override = String.fromEnvironment('MAP_STYLE_URL');
    if (override.isNotEmpty) return override;
    if (hasEdge && selfHostedTiles) return '$edgeBaseUrl/style.json${dark ? '?theme=dark' : ''}';
    return dark ? openFreeMapDarkStyle : openFreeMapStyle;
  }

  /// Store product ids for the premium subscription.
  static const premiumProductIds = {'convoy_premium_monthly', 'convoy_premium_yearly'};

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
