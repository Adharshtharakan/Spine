import type { Env } from "./env";
import { type LatLng, simplify } from "./geo";
import { HttpError, json, readJson } from "./http";

/**
 *   POST /route { points: [[lat,lng], …] } → road geometry through the stops
 *
 * Road-following geometry lets the app place a silent car on the road it is
 * actually driving, instead of on a straight line between stops. The phone
 * caches the result with the trip, so prediction keeps working offline.
 *
 * Backed by OSRM (OpenStreetMap). `OSRM_URL` should point at a self-hosted
 * instance in production; the public demo server is for development only.
 * Results are cached in KV, so a convoy's route is computed once.
 */
export async function handleRouting(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  if (req.method !== "POST" || new URL(req.url).pathname !== "/route") return null;
  const body = await readJson<{ points?: LatLng[] }>(req);
  const points = (body.points ?? []).filter(
    (p): p is LatLng => Array.isArray(p) && p.length === 2 && Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180,
  );
  if (points.length < 2) throw new HttpError(400, "need_two_points");
  if (points.length > 50) throw new HttpError(400, "too_many_points");

  const coords = points.map(([lat, lng]) => `${lng.toFixed(5)},${lat.toFixed(5)}`).join(";");
  const key = `route:v1:${coords}`;
  const hit = await env.CACHE.get(key, "json");
  if (hit) return json(hit);

  const base = env.OSRM_URL ?? "https://router.project-osrm.org";
  const res = await fetch(`${base}/route/v1/driving/${coords}?overview=full&geometries=geojson&steps=false`, {
    headers: { "user-agent": "convoy-edge/1.0" },
  });
  if (!res.ok) throw new HttpError(502, "routing_unavailable");
  const data = (await res.json()) as {
    code: string;
    routes?: { distance: number; duration: number; geometry: { coordinates: [number, number][] }; legs: { distance: number; duration: number }[] }[];
  };
  const route = data.routes?.[0];
  if (data.code !== "Ok" || !route) throw new HttpError(422, "no_route");

  const geometry = simplify(
    route.geometry.coordinates.map(([lng, lat]) => [lat, lng] as LatLng),
    30,
  ).map(([lat, lng]) => [Math.round(lat * 1e5) / 1e5, Math.round(lng * 1e5) / 1e5]);
  const out = {
    geometry,
    distance_m: Math.round(route.distance),
    duration_s: Math.round(route.duration),
    legs: route.legs.map((l) => ({ distance_m: Math.round(l.distance), duration_s: Math.round(l.duration) })),
  };
  ctx.waitUntil(env.CACHE.put(key, JSON.stringify(out), { expirationTtl: 60 * 60 * 24 * 30 }));
  return json(out);
}
