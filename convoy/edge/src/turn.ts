import { requireUser } from "./auth";
import type { Env } from "./env";
import { json } from "./http";

/**
 *   POST /turn → { iceServers: [...] }   short-lived TURN credentials
 *
 * Push-to-talk audio goes phone to phone. On mobile networks (carrier NAT)
 * a direct path often can't be found, so phones also get Cloudflare's TURN
 * relay. Credentials are minted per request and expire after a day; without
 * a TURN key configured, only public STUN servers are returned.
 */
export async function handleTurn(req: Request, env: Env): Promise<Response | null> {
  if (req.method !== "POST" || new URL(req.url).pathname !== "/turn") return null;
  await requireUser(req, env);
  const stun = { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] };
  if (!env.CF_TURN_KEY_ID || !env.CF_TURN_KEY_API_TOKEN) return json({ iceServers: [stun] });
  const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.CF_TURN_KEY_ID}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.CF_TURN_KEY_API_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ ttl: 86400 }),
  });
  if (!res.ok) return json({ iceServers: [stun] });
  return json({ iceServers: normalizeIceServers(await res.json()) });
}

type IceServer = { urls: string | string[]; username?: string; credential?: string };

/** Cloudflare returns either a list of servers or (older endpoint) a single object. */
export function normalizeIceServers(body: unknown): IceServer[] {
  const servers = (body as { iceServers?: IceServer | IceServer[] })?.iceServers;
  if (!servers) return [];
  return Array.isArray(servers) ? servers : [servers];
}
