import type { Env } from "./env";
import { corridor, distanceM, type LatLng, project } from "./geo";
import { HttpError, json, readJson } from "./http";

/**
 *   POST /tolls { geometry: [[lat,lng], …] } → toll plazas on the route
 *
 * Toll booths from OpenStreetMap (`barrier=toll_booth`) within 100 m of the
 * road, with booths of the same plaza (one node per lane) merged. OSM has no
 * reliable prices, so the app turns the plaza count into an estimate with a
 * per-plaza amount the organiser can adjust.
 */
export async function handleTolls(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  if (req.method !== "POST" || new URL(req.url).pathname !== "/tolls") return null;
  const body = await readJson<{ geometry?: LatLng[] }>(req);
  const route = (body.geometry ?? []).filter(
    (p): p is LatLng => Array.isArray(p) && p.length === 2 && Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180,
  );
  if (route.length < 2) throw new HttpError(400, "need_route");
  if (route.length > 5000) throw new HttpError(400, "route_too_long");

  const booths: TollNode[] = [];
  for (const b of corridor(route, 80_000, 300)) {
    const bbox = [b.south, b.west, b.north, b.east].map((v) => v.toFixed(3)).join(",");
    const key = `tolls:v1:${bbox}`;
    let els = await env.CACHE.get<TollNode[]>(key, "json");
    if (!els) {
      const q = `[out:json][timeout:25];node["barrier"="toll_booth"](${bbox});out tags 500;`;
      const res = await fetch(env.OVERPASS_URL ?? "https://overpass-api.de/api/interpreter", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": "convoy-edge/1.0" },
        body: `data=${encodeURIComponent(q)}`,
      });
      if (!res.ok) throw new HttpError(502, "toll_source_unavailable");
      els = ((await res.json()) as { elements?: TollNode[] }).elements ?? [];
      ctx.waitUntil(env.CACHE.put(key, JSON.stringify(els), { expirationTtl: 60 * 60 * 24 * 7 }));
    }
    booths.push(...els);
  }
  return json({ plazas: plazasOnRoute(route, booths) });
}

export interface TollNode {
  id: number;
  lat: number;
  lon: number;
  tags?: Record<string, string>;
}

export interface Plaza {
  name: string;
  lat: number;
  lng: number;
  along_km: number;
}

export function plazasOnRoute(route: LatLng[], booths: TollNode[]): Plaza[] {
  const near = booths
    .map((b) => ({ b, p: project(route, [b.lat, b.lon]) }))
    .filter(({ p }) => p.offM <= 100)
    .sort((x, y) => x.p.alongM - y.p.alongM);
  const plazas: Plaza[] = [];
  for (const { b, p } of near) {
    const last = plazas[plazas.length - 1];
    if (last && (p.alongM / 1000 - last.along_km) * 1000 < 500 && distanceM([last.lat, last.lng], [b.lat, b.lon]) < 800) continue;
    plazas.push({
      name: b.tags?.name ?? b.tags?.operator ?? "Toll plaza",
      lat: b.lat,
      lng: b.lon,
      along_km: Math.round(p.alongM / 100) / 10,
    });
  }
  return plazas;
}
