import { optionalUser, requireUser } from "./auth";
import type { Env } from "./env";
import { distanceM, type LatLng } from "./geo";
import { HttpError, json, num, readJson } from "./http";
import { Supabase } from "./supabase";

interface ListedTrip {
  id: string;
  title: string;
  summary: string;
  tags: string[];
  starts_at: string | null;
  start_lat: number;
  start_lng: number;
  end_lat: number;
  end_lng: number;
  owner_name: string;
  owner_verified: boolean;
  vehicle_count: number;
  open_slots: number;
}

interface Sponsor {
  id: string;
  partner_name: string;
  category: string;
  name: string;
  lat: number;
  lng: number;
  radius_km: number;
  url: string;
  weight: number;
}

/**
 * Public trip discovery.
 *
 *   GET  /discovery/trips?lat=&lng=&radius_km=&tags=a,b&from=ISO
 *   POST /discovery/trips/:id/join   { vehicle_label, message }
 *
 * Listing reads `discover_trips()` (a SECURITY DEFINER function that only
 * returns fields safe for strangers) and blends in sponsored placements from
 * tourism boards and highway businesses near the search area. Joining
 * forwards the caller's JWT to `request_to_join`, so the database enforces
 * guideline acceptance — the Worker adds no rules of its own.
 */
export async function handleDiscovery(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname === "/discovery/trips") return list(req, url, env, ctx);

  const m = /^\/discovery\/trips\/([0-9a-f-]{36})\/join$/.exec(url.pathname);
  if (req.method === "POST" && m) return join(req, m[1], env);
  return null;
}

async function list(req: Request, url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const lat = num(url.searchParams.get("lat"), "lat");
  const lng = num(url.searchParams.get("lng"), "lng");
  const radiusKm = Math.min(Number(url.searchParams.get("radius_km") ?? 300) || 300, 2000);
  const tags = (url.searchParams.get("tags") ?? "")
    .split(",")
    .map((t) => t.trim().toLowerCase())
    .filter(Boolean);
  const from = url.searchParams.get("from") ?? new Date().toISOString();
  await optionalUser(req, env); // validates a token if one is sent

  // Cache by a coarse grid so nearby searches share results for a minute.
  const cacheKey = new Request(
    `https://cache.convoy/discovery?lat=${lat.toFixed(1)}&lng=${lng.toFixed(1)}&r=${radiusKm}&t=${tags.sort().join(",")}&d=${from.slice(0, 10)}`,
  );
  const cached = await caches.default.match(cacheKey);
  if (cached) return cached;

  const dLat = radiusKm / 111.32;
  const dLng = radiusKm / (111.32 * Math.max(0.01, Math.cos((lat * Math.PI) / 180)));
  const db = new Supabase(env);
  const [trips, sponsors] = await Promise.all([
    db.rpc<ListedTrip[]>("discover_trips", {
      p_south: lat - dLat,
      p_north: lat + dLat,
      p_west: lng - dLng,
      p_east: lng + dLng,
      p_from: from,
      p_limit: 200,
    }),
    db.select<Sponsor>(
      "sponsored_placements",
      `select=id,partner_name,category,name,lat,lng,radius_km,url,weight&active=is.true&starts_at=lte.${new Date().toISOString()}&or=(ends_at.is.null,ends_at.gt.${new Date().toISOString()})&lat=gte.${lat - dLat}&lat=lte.${lat + dLat}&lng=gte.${lng - dLng}&lng=lte.${lng + dLng}`,
    ),
  ]);

  const here: LatLng = [lat, lng];
  const results = trips
    .map((t) => ({ ...t, distance_km: distanceM(here, [t.start_lat, t.start_lng]) / 1000, sponsored: false }))
    .filter((t) => t.distance_km <= radiusKm)
    .filter((t) => tags.length === 0 || tags.every((tag) => t.tags.map((x) => x.toLowerCase()).includes(tag)))
    .sort((a, b) => rank(a) - rank(b));

  const featured = sponsors
    .map((s) => ({ ...s, distance_km: distanceM(here, [s.lat, s.lng]) / 1000 }))
    .filter((s) => s.distance_km <= Math.max(s.radius_km, radiusKm))
    .sort((a, b) => b.weight - a.weight || a.distance_km - b.distance_km)
    .slice(0, 5);

  const res = json({ trips: results, sponsored: featured }, { headers: { "cache-control": "public, max-age=60" } });
  ctx.waitUntil(caches.default.put(cacheKey, res.clone()));
  return res;
}

/** Lower is better: soon, nearby, verified organisers and trips with room. */
function rank(t: { distance_km: number; starts_at: string | null; owner_verified: boolean; open_slots: number }): number {
  const days = t.starts_at ? Math.max(0, (Date.parse(t.starts_at) - Date.now()) / 86_400_000) : 30;
  return t.distance_km / 50 + days / 7 + (t.owner_verified ? 0 : 3) + (t.open_slots > 0 ? 0 : 100);
}

async function join(req: Request, tripId: string, env: Env): Promise<Response> {
  const user = await requireUser(req, env);
  const body = await readJson<{ vehicle_label?: string; message?: string }>(req);
  const label = (body.vehicle_label ?? "").trim();
  if (!label) throw new HttpError(400, "vehicle_label_required");
  const row = await new Supabase(env).rpc(
    "request_to_join",
    { p_trip: tripId, p_vehicle_label: label.slice(0, 40), p_message: (body.message ?? "").slice(0, 500) },
    user.token,
  );
  return json({ request: row }, { status: 201 });
}
