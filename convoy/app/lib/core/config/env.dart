/// Build-time configuration, injected with `--dart-define-from-file=env.json`
/// (see `env.example.json`). Nothing secret lives in the app: the Supabase
/// anon key is public by design and every table is protected by RLS.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Cloudflare Worker base URL — tiles, discovery, affiliates, billing.
  static const edgeBaseUrl =
      String.fromEnvironment('EDGE_BASE_URL', defaultValue: 'https://convoy-edge.example.workers.dev');

  /// MapLibre style served by the Worker from the self-hosted PMTiles archive.
  static String get mapStyleUrl => const String.fromEnvironment('MAP_STYLE_URL').isNotEmpty
      ? const String.fromEnvironment('MAP_STYLE_URL')
      : '$edgeBaseUrl/style.json';

  /// Optional TURN relay for voice when both peers sit behind symmetric NAT.
  /// STUN alone keeps media peer-to-peer at zero cost.
  static const turnUrl = String.fromEnvironment('TURN_URL');
  static const turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  /// Store product ids for the premium subscription.
  static const premiumProductIds = {'convoy_premium_monthly', 'convoy_premium_yearly'};

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
