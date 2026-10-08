import { decodeJwt, importPKCS8, SignJWT } from "jose";
import { requireUser } from "./auth";
import type { Env } from "./env";
import { HttpError, json, readJson } from "./http";
import { Supabase } from "./supabase";

/**
 * Freemium subscription verification.
 *
 *   POST /billing/verify          { platform, product_id, purchase_id, verification_data }  (user JWT)
 *   POST /billing/apple/notify    App Store Server Notifications V2
 *   POST /billing/google/rtdn     Google Play RTDN (Pub/Sub push)
 *
 * The device's purchase result is never trusted: each path asks Google or
 * Apple directly, then writes `entitlements` with the service role. The
 * notification endpoints only use the payload to learn *which* purchase
 * changed and re-fetch it from the store, so a forged notification can at
 * worst trigger a harmless refresh.
 */
export async function handleBilling(req: Request, env: Env): Promise<Response | null> {
  const path = new URL(req.url).pathname;
  if (req.method !== "POST") return null;
  if (path === "/billing/verify") return verifyPurchase(req, env);
  if (path === "/billing/apple/notify") return appleNotify(req, env);
  if (path === "/billing/google/rtdn") return googleRtdn(req, env);
  return null;
}

const PREMIUM_PRODUCTS = new Set(["convoy_premium_monthly", "convoy_premium_yearly"]);

interface Grant {
  userId: string;
  source: "google_play" | "app_store";
  productId: string;
  originalTransactionId: string;
  expiresAt: Date;
  active: boolean;
}

async function verifyPurchase(req: Request, env: Env): Promise<Response> {
  const user = await requireUser(req, env);
  const body = await readJson<{ platform?: string; product_id?: string; purchase_id?: string; verification_data?: string }>(req);
  if (!body.product_id || !PREMIUM_PRODUCTS.has(body.product_id)) throw new HttpError(400, "unknown_product");

  let grant: Grant;
  if (body.platform === "google_play") {
    if (!body.verification_data) throw new HttpError(400, "missing_purchase_token");
    grant = await googleSubscription(env, body.verification_data, user.id);
  } else if (body.platform === "app_store") {
    const txId = body.purchase_id ?? appleTransactionIdFromJws(body.verification_data);
    if (!txId) throw new HttpError(400, "missing_transaction_id");
    grant = await appleTransaction(env, txId, user.id);
  } else {
    throw new HttpError(400, "unknown_platform");
  }
  await writeEntitlement(env, grant);
  return json({ tier: grant.active ? "premium" : "free", expires_at: grant.expiresAt.toISOString() });
}

async function writeEntitlement(env: Env, g: Grant): Promise<void> {
  await new Supabase(env).upsert(
    "entitlements",
    {
      user_id: g.userId,
      tier: g.active ? "premium" : "free",
      expires_at: g.expiresAt.toISOString(),
      source: g.source,
      product_id: g.productId,
      original_transaction_id: `${g.source}:${g.originalTransactionId}`,
      updated_at: new Date().toISOString(),
    },
    "user_id",
  );
}

// ─────────────────────────────── Google ───────────────────────────────

let googleToken: { value: string; exp: number } | undefined;

async function googleAccessToken(env: Env): Promise<string> {
  if (googleToken && googleToken.exp > Date.now() + 60_000) return googleToken.value;
  if (!env.GOOGLE_SERVICE_ACCOUNT_JSON) throw new HttpError(503, "google_billing_not_configured");
  const sa = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as { client_email: string; private_key: string };
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/androidpublisher" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${assertion}`,
  });
  if (!res.ok) throw new HttpError(502, "google_auth_failed");
  const t = (await res.json()) as { access_token: string; expires_in: number };
  googleToken = { value: t.access_token, exp: Date.now() + t.expires_in * 1000 };
  return t.access_token;
}

interface GoogleSubV2 {
  subscriptionState: string;
  lineItems?: { productId: string; expiryTime: string }[];
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  latestOrderId?: string;
}

async function googleSubscription(env: Env, purchaseToken: string, expectedUser?: string): Promise<Grant> {
  const pkg = env.ANDROID_PACKAGE_NAME ?? "app.convoy.convoy";
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: { authorization: `Bearer ${await googleAccessToken(env)}` } },
  );
  if (res.status === 404 || res.status === 400) throw new HttpError(400, "purchase_not_found");
  if (!res.ok) throw new HttpError(502, "google_verify_failed");
  const sub = (await res.json()) as GoogleSubV2;
  const item = (sub.lineItems ?? []).find((l) => PREMIUM_PRODUCTS.has(l.productId));
  if (!item) throw new HttpError(400, "unknown_product");

  // The app sets applicationUserName = Supabase user id, which Play stores
  // as the obfuscated account id. It binds the purchase to one account.
  const owner = sub.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  if (!owner) throw new HttpError(400, "purchase_not_bound_to_account");
  if (expectedUser && owner !== expectedUser) throw new HttpError(403, "purchase_belongs_to_another_account");

  const expiresAt = new Date(item.expiryTime);
  const active =
    ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"].includes(sub.subscriptionState) ||
    (sub.subscriptionState === "SUBSCRIPTION_STATE_CANCELED" && expiresAt.getTime() > Date.now());
  return {
    userId: owner,
    source: "google_play",
    productId: item.productId,
    originalTransactionId: purchaseToken.slice(0, 120),
    expiresAt,
    active,
  };
}

/** Pub/Sub push: { message: { data: base64(JSON{ subscriptionNotification:{ purchaseToken } }) } } */
async function googleRtdn(req: Request, env: Env): Promise<Response> {
  const body = await readJson<{ message?: { data?: string } }>(req);
  try {
    const data = JSON.parse(atob(body.message?.data ?? "")) as {
      packageName?: string;
      subscriptionNotification?: { purchaseToken?: string };
    };
    const token = data.subscriptionNotification?.purchaseToken;
    if (token) await writeEntitlement(env, await googleSubscription(env, token));
  } catch (e) {
    console.error("rtdn", e);
  }
  return new Response(null, { status: 204 }); // always ack so Pub/Sub does not retry forever
}

// ─────────────────────────────── Apple ────────────────────────────────

async function appleApiToken(env: Env): Promise<string> {
  if (!env.APPLE_PRIVATE_KEY || !env.APPLE_KEY_ID || !env.APPLE_ISSUER_ID || !env.APPLE_BUNDLE_ID) {
    throw new HttpError(503, "apple_billing_not_configured");
  }
  const key = await importPKCS8(env.APPLE_PRIVATE_KEY, "ES256");
  return new SignJWT({ bid: env.APPLE_BUNDLE_ID })
    .setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID, typ: "JWT" })
    .setIssuer(env.APPLE_ISSUER_ID)
    .setAudience("appstoreconnect-v1")
    .setIssuedAt()
    .setExpirationTime("20m")
    .sign(key);
}

function appleHost(env: Env): string {
  return env.APPLE_ENVIRONMENT === "Sandbox"
    ? "https://api.storekit-sandbox.itunes.apple.com"
    : "https://api.storekit.itunes.apple.com";
}

function appleTransactionIdFromJws(jws?: string): string | undefined {
  if (!jws || jws.split(".").length !== 3) return undefined;
  try {
    return String(decodeJwt(jws).transactionId ?? "") || undefined;
  } catch {
    return undefined;
  }
}

interface AppleTx {
  bundleId: string;
  productId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
}

async function appleTransaction(env: Env, transactionId: string, expectedUser?: string): Promise<Grant> {
  const res = await fetch(`${appleHost(env)}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
    headers: { authorization: `Bearer ${await appleApiToken(env)}` },
  });
  if (res.status === 404) throw new HttpError(400, "purchase_not_found");
  if (!res.ok) throw new HttpError(502, "apple_verify_failed");
  const { signedTransactionInfo } = (await res.json()) as { signedTransactionInfo: string };
  // Fetched over TLS straight from Apple's API, so the JWS contents are
  // authentic; decoding is sufficient here.
  const tx = decodeJwt(signedTransactionInfo) as unknown as AppleTx;
  if (tx.bundleId !== env.APPLE_BUNDLE_ID) throw new HttpError(400, "wrong_bundle");
  if (!PREMIUM_PRODUCTS.has(tx.productId)) throw new HttpError(400, "unknown_product");

  // The app passes the Supabase user id (a UUID) as appAccountToken. Without
  // it anyone could submit someone else's transaction id and claim Premium.
  const owner = tx.appAccountToken?.toLowerCase();
  if (!owner) throw new HttpError(400, "purchase_not_bound_to_account");
  if (expectedUser && owner !== expectedUser) {
    throw new HttpError(403, "purchase_belongs_to_another_account");
  }
  const expiresAt = new Date(tx.expiresDate ?? 0);
  return {
    userId: owner,
    source: "app_store",
    productId: tx.productId,
    originalTransactionId: tx.originalTransactionId,
    expiresAt,
    active: !tx.revocationDate && expiresAt.getTime() > Date.now(),
  };
}

/** App Store Server Notifications V2: { signedPayload } → data.signedTransactionInfo */
async function appleNotify(req: Request, env: Env): Promise<Response> {
  const body = await readJson<{ signedPayload?: string }>(req);
  try {
    const payload = decodeJwt(body.signedPayload ?? "") as { data?: { signedTransactionInfo?: string } };
    const txId = appleTransactionIdFromJws(payload.data?.signedTransactionInfo);
    // Re-fetch from Apple: the notification only tells us what to refresh.
    if (txId) {
      const grant = await appleTransaction(env, txId);
      await writeEntitlement(env, grant);
    }
  } catch (e) {
    console.error("apple notify", e);
  }
  return new Response(null, { status: 200 });
}
