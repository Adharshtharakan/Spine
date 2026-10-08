export interface Env {
  /** R2 bucket holding the PMTiles basemap plus fonts and sprites. */
  TILES: R2Bucket;
  /** Object key of the PMTiles archive inside TILES. */
  PMTILES_KEY: string;
  /** Workers KV for POI corridor results and other short-lived caches. */
  CACHE: KVNamespace;

  SUPABASE_URL: string;
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

  /** Google Play Developer API service account (JSON) for purchase checks. */
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;
  ANDROID_PACKAGE_NAME?: string;
  /** App Store Server API credentials. */
  APPLE_ISSUER_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_ENVIRONMENT?: "Production" | "Sandbox";

  /** Public base for fonts/sprites when they are not mirrored in R2. */
  ASSETS_FALLBACK_URL?: string;
}
