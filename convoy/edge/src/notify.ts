import { requireUser } from "./auth";
import type { Env } from "./env";
import { googleAccessToken, parseServiceAccount } from "./google";
import { HttpError, json, readJson } from "./http";
import { Supabase } from "./supabase";

/**
 *   POST /notify  { trip_id, kind, title, body, to? }  push to the rest of the party
 *   POST /sos/sms { trip_id, to: ["+91…"], body }      SOS text to emergency contacts
 *
 * The app calls /notify when something happens that people who do not have
 * the trip open should hear about: an SOS, a hazard, a join request, a
 * regroup point, a plan change. The caller must be a member of the trip and
 * only members receive it. Delivery is Firebase Cloud Messaging (HTTP v1);
 * tokens Firebase reports as unregistered are deleted.
 *
 * /sos/sms sends through Twilio when configured, and only for a caller who
 * raised an SOS in that trip in the last 10 minutes, so it cannot be used as
 * a general SMS relay.
 */
export async function handleNotify(req: Request, env: Env): Promise<Response | null> {
  const path = new URL(req.url).pathname;
  if (req.method !== "POST" || (path !== "/notify" && path !== "/sos/sms")) return null;
  const user = await requireUser(req, env);
  return path === "/notify" ? notify(req, env, user.id) : sosSms(req, env, user.id);
}

export const KINDS = ["sos", "hazard", "regroup", "headcount", "join_request", "member_joined", "plan", "alert"] as const;
export type Kind = (typeof KINDS)[number];

interface NotifyBody {
  trip_id?: string;
  kind?: string;
  title?: string;
  body?: string;
  to?: string[];
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function notify(req: Request, env: Env, userId: string): Promise<Response> {
  const b = await readJson<NotifyBody>(req);
  if (!b.trip_id || !UUID.test(b.trip_id)) throw new HttpError(400, "bad_trip");
  if (!KINDS.includes(b.kind as Kind)) throw new HttpError(400, "bad_kind");
  const title = (b.title ?? "").trim().slice(0, 80);
  const text = (b.body ?? "").trim().slice(0, 240);
  if (!title) throw new HttpError(400, "missing_title");

  const sb = new Supabase(env);
  const members = await sb.select<{ user_id: string }>("trip_members", `trip_id=eq.${b.trip_id}&select=user_id`);
  const ids = members.map((m) => m.user_id);
  if (!ids.includes(userId)) throw new HttpError(403, "not_a_member");

  // A soft per-user limit: SOS always goes through.
  if (b.kind !== "sos") await rateLimit(env, `notify:${userId}`, 30);

  const wanted = new Set((b.to ?? []).filter((id) => UUID.test(id)));
  const recipients = ids.filter((id) => id !== userId && (wanted.size === 0 || wanted.has(id)));
  if (recipients.length === 0) return json({ sent: 0 });
  return json({ sent: await pushToUsers(env, recipients, b.kind as Kind, title, text, b.trip_id) });
}

/** Sends a push to every registered phone of [userIds]; drops dead tokens. */
export async function pushToUsers(env: Env, userIds: string[], kind: Kind, title: string, body: string, tripId: string): Promise<number> {
  if (userIds.length === 0) return 0;
  const sb = new Supabase(env);
  const tokens = await sb.select<{ token: string }>("device_tokens", `user_id=in.(${userIds.join(",")})&select=token`);
  if (tokens.length === 0) return 0;
  const sa = parseServiceAccount(env.FCM_SERVICE_ACCOUNT_JSON ?? env.GOOGLE_SERVICE_ACCOUNT_JSON, "push_not_configured");
  const access = await googleAccessToken(sa, "https://www.googleapis.com/auth/firebase.messaging");
  let sent = 0;
  const stale: string[] = [];
  await Promise.all(
    tokens.map(async ({ token }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
        body: JSON.stringify({ message: fcmMessage(token, kind, title, body, tripId) }),
      });
      if (res.ok) sent++;
      else if (res.status === 404 || res.status === 400) stale.push(token);
    }),
  );
  if (stale.length) await sb.delete("device_tokens", `token=in.(${stale.map((t) => `"${t}"`).join(",")})`);
  return sent;
}

export function fcmMessage(token: string, kind: Kind, title: string, body: string, tripId: string) {
  const urgent = kind === "sos";
  return {
    token,
    notification: { title, body },
    data: { trip_id: tripId, kind },
    android: {
      priority: urgent || kind === "hazard" ? "high" : "normal",
      notification: { channel_id: urgent ? "sos" : "convoy", tag: `${tripId}:${kind}` },
    },
    apns: { payload: { aps: { sound: urgent ? "default" : undefined, "interruption-level": urgent ? "time-sensitive" : "active" } } },
  };
}

async function rateLimit(env: Env, key: string, perMinute: number): Promise<void> {
  const k = `${key}:${Math.floor(Date.now() / 60_000)}`;
  const n = Number((await env.CACHE.get(k)) ?? 0);
  if (n >= perMinute) throw new HttpError(429, "too_many_notifications");
  await env.CACHE.put(k, String(n + 1), { expirationTtl: 120 });
}

// ──────────────────────────────── SOS SMS ───────────────────────────────

const E164 = /^\+[1-9]\d{6,14}$/;

async function sosSms(req: Request, env: Env, userId: string): Promise<Response> {
  if (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_FROM) throw new HttpError(503, "sms_not_configured");
  const b = await readJson<{ trip_id?: string; to?: string[]; body?: string }>(req);
  if (!b.trip_id || !UUID.test(b.trip_id)) throw new HttpError(400, "bad_trip");
  const to = [...new Set((b.to ?? []).map((n) => n.replace(/[\s()-]/g, "")))].filter((n) => E164.test(n));
  if (to.length === 0) throw new HttpError(400, "no_valid_numbers");
  if (to.length > 5) throw new HttpError(400, "too_many_numbers");
  const text = (b.body ?? "").trim().slice(0, 320);
  if (!text) throw new HttpError(400, "missing_body");

  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const sos = await new Supabase(env).select<{ id: string }>(
    "trip_events",
    `trip_id=eq.${b.trip_id}&kind=eq.sos&created_by=eq.${userId}&created_at=gte.${since}&select=id&limit=1`,
  );
  if (sos.length === 0) throw new HttpError(403, "no_active_sos");
  await rateLimit(env, `sms:${userId}`, 10);

  const auth = btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`);
  let sent = 0;
  for (const number of to) {
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`, {
      method: "POST",
      headers: { authorization: `Basic ${auth}`, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ To: number, From: env.TWILIO_FROM, Body: text }),
    });
    if (res.ok) sent++;
  }
  return json({ sent });
}
