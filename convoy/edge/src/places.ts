import type { Env } from "./env";
import { HttpError, json, num } from "./http";

/**
 *   GET /places/search?q=…&lat=…&lng=…   place search for adding stops
 *   GET /places/reverse?lat=…&lng=…      name for a point (long-press on map)
 *
 * Backed by Photon (OpenStreetMap). `PHOTON_URL` should point at a
 * self-hosted instance in production; the public komoot server has a fair-use
 * limit. Results are cached in KV for a day, and searches are biased towards
 * the caller's position so "Shell" finds the nearby one first.
 */
export async function handlePlaces(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  const url = new URL(req.url);
  if (req.method !== "GET" || !url.pathname.startsWith("/places/")) return null;
  const base = env.PHOTON_URL ?? "https://photon.komoot.io";
  if (url.pathname === "/places/search") {
    const q = (url.searchParams.get("q") ?? "").trim();
    if (q.length < 2) throw new HttpError(400, "query_too_short");
    if (q.length > 120) throw new HttpError(400, "query_too_long");
    const params = new URLSearchParams({ q, limit: "8", lang: "en" });
    if (url.searchParams.has("lat") && url.searchParams.has("lng")) {
      params.set("lat", num(url.searchParams.get("lat"), "lat").toFixed(3));
      params.set("lon", num(url.searchParams.get("lng"), "lng").toFixed(3));
    }
    return json({ places: await photon(env, ctx, `${base}/api/?${params}`) });
  }
  if (url.pathname === "/places/reverse") {
    const lat = num(url.searchParams.get("lat"), "lat");
    const lng = num(url.searchParams.get("lng"), "lng");
    const params = new URLSearchParams({ lat: lat.toFixed(5), lon: lng.toFixed(5), lang: "en" });
    const [place] = await photon(env, ctx, `${base}/reverse?${params}`);
    return json({ place: place ?? null });
  }
  return null;
}

export interface Place {
  name: string;
  /** Second line: locality, region, country. */
  detail: string;
  lat: number;
  lng: number;
  /** OSM key/value, e.g. "amenity:fuel", to suggest a stop kind. */
  type: string;
}

interface PhotonFeature {
  geometry: { coordinates: [number, number] };
  properties: Record<string, string | undefined>;
}

async function photon(env: Env, ctx: ExecutionContext, target: string): Promise<Place[]> {
  const key = `places:v1:${target}`;
  const hit = await env.CACHE.get<Place[]>(key, "json");
  if (hit) return hit;
  const res = await fetch(target, { headers: { "user-agent": "convoy-edge/1.0" } });
  if (!res.ok) throw new HttpError(502, "places_unavailable");
  const body = (await res.json()) as { features?: PhotonFeature[] };
  const places = (body.features ?? []).map(toPlace).filter((p): p is Place => p !== null);
  ctx.waitUntil(env.CACHE.put(key, JSON.stringify(places), { expirationTtl: 60 * 60 * 24 }));
  return places;
}

export function toPlace(f: PhotonFeature): Place | null {
  const p = f.properties;
  const [lng, lat] = f.geometry?.coordinates ?? [];
  if (typeof lat !== "number" || typeof lng !== "number") return null;
  const street = [p.street, p.housenumber].filter(Boolean).join(" ");
  const name = p.name ?? (street || p.city || p.county);
  if (!name) return null;
  const detail = [p.name ? street : "", p.district, p.city ?? p.town ?? p.village, p.state, p.country]
    .filter((s): s is string => !!s && s !== name)
    .filter((s, i, a) => a.indexOf(s) === i)
    .join(", ");
  return {
    name,
    detail,
    lat: Math.round(lat * 1e6) / 1e6,
    lng: Math.round(lng * 1e6) / 1e6,
    type: `${p.osm_key ?? ""}:${p.osm_value ?? ""}`,
  };
}
