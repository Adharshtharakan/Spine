import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";
import type { Env } from "./env";
import { HttpError } from "./http";

export interface AuthedUser {
  id: string;
  token: string;
  claims: JWTPayload;
}

let jwks: { url: string; set: ReturnType<typeof createRemoteJWKSet> } | undefined;

/**
 * Verifies the caller's Supabase access token locally — no round trip to
 * Supabase Auth. Supports both the asymmetric signing keys (JWKS) and the
 * legacy shared HS256 secret.
 */
export async function requireUser(req: Request, env: Env): Promise<AuthedUser> {
  const header = req.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new HttpError(401, "missing_token");

  const issuer = `${env.SUPABASE_URL}/auth/v1`;
  try {
    let payload: JWTPayload;
    if (env.SUPABASE_JWT_SECRET) {
      ({ payload } = await jwtVerify(token, new TextEncoder().encode(env.SUPABASE_JWT_SECRET), {
        issuer,
        audience: "authenticated",
      }));
    } else {
      const url = `${issuer}/.well-known/jwks.json`;
      if (!jwks || jwks.url !== url) jwks = { url, set: createRemoteJWKSet(new URL(url)) };
      ({ payload } = await jwtVerify(token, jwks.set, { issuer, audience: "authenticated" }));
    }
    if (!payload.sub) throw new Error("no_sub");
    return { id: payload.sub, token, claims: payload };
  } catch {
    throw new HttpError(401, "invalid_token");
  }
}

export async function optionalUser(req: Request, env: Env): Promise<AuthedUser | null> {
  if (!req.headers.get("authorization")) return null;
  return requireUser(req, env);
}
