export interface Env {
  /** R2 bucket holding the PMTiles basemap plus fonts and sprites. */
  TILES?: R2Bucket;
  /** Object key of the PMTiles archive inside TILES. */
  PMTILES_KEY: string;
  /** Workers KV for POI corridor results and other short-lived caches. */
  CACHE: KVNamespace;

  SUPABASE_URL: string;
  /** Public anon key, sent as `apikey` when calling PostgREST as the user. */
  SUPABASE_ANON_KEY: string;
  /** Service-role key: used only for writes the client may not make itself. */
  SUPABASE_SERVICE_ROLE_KEY: string;
  /** Legacy HS256 JWT secret. Leave empty when the project uses JWKS signing keys. */
  SUPABASE_JWT_SECRET?: string;

  /** HMAC key for signed affiliate click links and partner postbacks. */
  AFFILIATE_SIGNING_KEY: string;
  /** Partner ids; any left empty disables that partner's deep links. */
  BOOKING_AFFILIATE_ID?: string;
  HIPCAMP_AFFILIATE_ID?: string;
  OVERPASS_URL?: string;
  /** OSRM routing server for road geometry (self-host in production). */
  OSRM_URL?: string;

  /** Google Play Developer API service account (JSON) for purchase checks. */
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;
  ANDROID_PACKAGE_NAME?: string;
  /** App Store Server API credentials. */
  APPLE_ISSUER_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_ENVIRONMENT?: "Production" | "Sandbox";

  /** Photon geocoder (place search). Self-host in production. */
  PHOTON_URL?: string;
  /** Open-Meteo forecast API base (weather along the route). */
  OPEN_METEO_URL?: string;

  /** Firebase service account (JSON) for push notifications; falls back to GOOGLE_SERVICE_ACCOUNT_JSON. */
  FCM_SERVICE_ACCOUNT_JSON?: string;

  /** Cloudflare Realtime TURN key (push-to-talk relay on mobile networks). */
  CF_TURN_KEY_ID?: string;
  CF_TURN_KEY_API_TOKEN?: string;

  /** Optional Twilio account for SOS text messages to emergency contacts. */
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_FROM?: string;

  /** App links: the signing certificate's SHA-256 fingerprint(s), comma separated. */
  ANDROID_CERT_SHA256?: string;
  /** Apple team id + bundle id for universal links, e.g. "ABCDE12345.com.example.drivesync". */
  APPLE_APP_ID?: string;
  /** Store pages shown on the invite landing page. */
  PLAY_STORE_URL?: string;
  APP_STORE_URL?: string;

  /** Public base for fonts/sprites when they are not mirrored in R2. */
  ASSETS_FALLBACK_URL?: string;
}
