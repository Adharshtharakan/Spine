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

  /// Set to true once the self-hosted PMTiles basemap is in R2.
  static const selfHostedTiles = bool.fromEnvironment('SELF_HOSTED_TILES');

  /// Free, key-less OpenStreetMap vector tiles (openfreemap.org): lets the
  /// app run before any map infrastructure exists.
  static const openFreeMapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  /// Map style: explicit override → self-hosted Protomaps via the Worker →
  /// OpenFreeMap.
  static String get mapStyleUrl {
    const override = String.fromEnvironment('MAP_STYLE_URL');
    if (override.isNotEmpty) return override;
    if (hasEdge && selfHostedTiles) return '$edgeBaseUrl/style.json';
    return openFreeMapStyle;
  }

  /// Whether the style understands `?theme=dark` (only our Worker's does).
  static bool get styleSupportsDarkTheme =>
      const String.fromEnvironment('MAP_STYLE_URL').isEmpty && hasEdge && selfHostedTiles;

  /// Optional TURN relay for voice when both peers sit behind symmetric NAT.
  /// STUN alone keeps media peer-to-peer at zero cost.
  static const turnUrl = String.fromEnvironment('TURN_URL');
  static const turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  /// Store product ids for the premium subscription.
  static const premiumProductIds = {'convoy_premium_monthly', 'convoy_premium_yearly'};

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
