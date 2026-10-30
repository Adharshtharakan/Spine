import { importPKCS8, SignJWT } from "jose";
import { HttpError } from "./http";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

const tokens = new Map<string, { value: string; exp: number }>();

export function parseServiceAccount(json: string | undefined, missing: string): ServiceAccount {
  if (!json) throw new HttpError(503, missing);
  return JSON.parse(json) as ServiceAccount;
}

/**
 * OAuth access token for a Google service account (JWT bearer grant),
 * cached per account and scope until a minute before it expires.
 */
export async function googleAccessToken(sa: ServiceAccount, scope: string): Promise<string> {
  const cacheKey = `${sa.client_email} ${scope}`;
  const hit = tokens.get(cacheKey);
  if (hit && hit.exp > Date.now() + 60_000) return hit.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope })
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
  tokens.set(cacheKey, { value: t.access_token, exp: Date.now() + t.expires_in * 1000 });
  return t.access_token;
}
