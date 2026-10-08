import { optionalUser } from "./auth";
import type { Env } from "./env";
import { corridor, type LatLng, project, simplify } from "./geo";
import { HttpError, json, readJson } from "./http";
import { sign, verify } from "./sign";
import { Supabase } from "./supabase";

export type Category = "hotel" | "campsite" | "fuel" | "rest_area";

export interface Offer {
  id: string;
  category: Category;
  name: string;
  lat: number;
  lng: number;
  provider: string;
  detour_km: number;
  along_km: number;
  brand?: string;
  price_hint?: string;
  booking_url?: string;
  sponsored: boolean;
}

/** How far off the route each category is still worth showing. */
const MAX_DETOUR_M: Record<Category, number> = {
  fuel: 2_000,
  rest_area: 1_000,
  hotel: 8_000,
  campsite: 15_000,
};

const OSM_FILTERS: Record<Category, string[]> = {
  fuel: ['nwr["amenity"="fuel"]'],
  rest_area: ['nwr["highway"="rest_area"]', 'nwr["highway"="services"]'],
  hotel: ['nwr["tourism"~"^(hotel|motel|guest_house)$"]'],
  campsite: ['nwr["tourism"~"^(camp_site|caravan_site)$"]'],
};

/**
 * B2B affiliate integrations.
 *
 *   POST /affiliates/along-route  { route: [[lat,lng],…], categories?, trip_id? }
 *   GET  /affiliates/click?…&sig=  → logs the click, 302 to the partner
 *   POST /affiliates/postback      ← partner conversion callback (HMAC)
 *
 * Places come from OpenStreetMap via Overpass (free, cached in KV per
 * corridor box). Bookable categories get a partner deep link wrapped in a
 * signed click URL, so every booking that pays commission is attributed to
 * the click (and trip) that produced it. Sponsored placements in range are
 * merged in and flagged.
 */
export async function handleAffiliates(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  const url = new URL(req.url);
  if (req.method === "POST" && url.pathname === "/affiliates/along-route") return alongRoute(req, url, env, ctx);
  if (req.method === "GET" && url.pathname === "/affiliates/click") return click(url, env, ctx);
  if (req.method === "POST" && url.pathname === "/affiliates/postback") return postback(req, env);
  return null;
}

async function alongRoute(req: Request, url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const user = await optionalUser(req, env);
  const body = await readJson<{ route?: LatLng[]; categories?: Category[]; trip_id?: string }>(req);
  const raw = (body.route ?? []).filter(
    (p): p is LatLng => Array.isArray(p) && p.length === 2 && Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180,
  );
  if (raw.length === 0) throw new HttpError(400, "route_required");
  const route = simplify(raw, 500).slice(0, 2000);
  const categories = (body.categories?.length ? body.categories : (Object.keys(OSM_FILTERS) as Category[])).filter(
    (c) => c in OSM_FILTERS,
  );

  const boxes = corridor(route, 80_000, Math.max(...categories.map((c) => MAX_DETOUR_M[c])));
  if (boxes.length > 25) throw new HttpError(413, "route_too_long");

  const elements = (await Promise.all(boxes.map((b) => overpass(env, ctx, b, categories)))).flat();
  const seen = new Set<string>();
  const offers: Offer[] = [];
  for (const el of elements) {
    const key = `${el.type}/${el.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const offer = toOffer(el, route);
    if (offer && categories.includes(offer.category)) offers.push(offer);
  }

  const sponsors = await sponsoredNear(env, route, categories);
  const all = [...sponsors, ...offers];

  const origin = url.origin;
  for (const o of all) {
    const target = partnerUrl(env, o);
    if (target) o.booking_url = await clickUrl(env, origin, o, target, body.trip_id, user?.id);
  }

  all.sort((a, b) => Number(b.sponsored) - Number(a.sponsored) || a.along_km - b.along_km);
  return json({ offers: all.slice(0, 300) });
}

// ─────────────────────────────── Overpass ───────────────────────────────

interface OsmElement {
  type: string;
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

async function overpass(env: Env, ctx: ExecutionContext, b: { south: number; west: number; north: number; east: number }, cats: Category[]): Promise<OsmElement[]> {
  const bbox = [b.south, b.west, b.north, b.east].map((v) => v.toFixed(3)).join(",");
  const key = `osm:v1:${cats.slice().sort().join("+")}:${bbox}`;
  const hit = await env.CACHE.get<OsmElement[]>(key, "json");
  if (hit) return hit;

  const parts = cats.flatMap((c) => OSM_FILTERS[c].map((f) => `${f}(${bbox});`)).join("");
  const q = `[out:json][timeout:25];(${parts});out center tags 400;`;
  const res = await fetch(env.OVERPASS_URL ?? "https://overpass-api.de/api/interpreter", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": "convoy-edge/1.0" },
    body: `data=${encodeURIComponent(q)}`,
  });
  if (!res.ok) throw new HttpError(502, "poi_source_unavailable");
  const els = ((await res.json()) as { elements: OsmElement[] }).elements ?? [];
  ctx.waitUntil(env.CACHE.put(key, JSON.stringify(els), { expirationTtl: 60 * 60 * 24 * 7 }));
  return els;
}

export function categorize(tags: Record<string, string>): Category | null {
  if (tags.amenity === "fuel") return "fuel";
  if (tags.highway === "rest_area" || tags.highway === "services") return "rest_area";
  if (["hotel", "motel", "guest_house"].includes(tags.tourism)) return "hotel";
  if (["camp_site", "caravan_site"].includes(tags.tourism)) return "campsite";
  return null;
}

export function toOffer(el: OsmElement, route: LatLng[]): Offer | null {
  const lat = el.lat ?? el.center?.lat;
  const lng = el.lon ?? el.center?.lon;
  const tags = el.tags ?? {};
  const category = categorize(tags);
  if (lat == null || lng == null || !category) return null;
  const { alongM, offM } = project(route, [lat, lng]);
  if (offM > MAX_DETOUR_M[category]) return null;
  const name =
    tags.name ?? tags.brand ?? { fuel: "Fuel station", rest_area: "Rest area", hotel: "Hotel", campsite: "Campsite" }[category];
  return {
    id: `osm:${el.type}/${el.id}`,
    category,
    name,
    lat,
    lng,
    provider: "openstreetmap",
    brand: tags.brand,
    detour_km: Math.round(offM / 100) / 10,
    along_km: Math.round(alongM / 100) / 10,
    sponsored: false,
  };
}

// ───────────────────────────── partners ─────────────────────────────

/**
 * Partner deep links. Booking.com and Hipcamp are wired as examples of the
 * hotel and campsite programmes; each is enabled only when its affiliate id
 * is configured, so unconfigured partners cost nothing and show plain POIs.
 */
export function partnerUrl(env: Env, o: Offer): string | null {
  if (o.sponsored && o.booking_url) return o.booking_url;
  if (o.category === "hotel" && env.BOOKING_AFFILIATE_ID) {
    const u = new URL("https://www.booking.com/searchresults.html");
    u.searchParams.set("aid", env.BOOKING_AFFILIATE_ID);
    u.searchParams.set("ss", o.name);
    u.searchParams.set("latitude", o.lat.toFixed(5));
    u.searchParams.set("longitude", o.lng.toFixed(5));
    u.searchParams.set("radius", "2");
    return u.toString();
  }
  if (o.category === "campsite" && env.HIPCAMP_AFFILIATE_ID) {
    const u = new URL("https://www.hipcamp.com/en-US/search");
    u.searchParams.set("lat", o.lat.toFixed(5));
    u.searchParams.set("lng", o.lng.toFixed(5));
    u.searchParams.set("irclickid", env.HIPCAMP_AFFILIATE_ID);
    return u.toString();
  }
  return null;
}

async function clickUrl(env: Env, origin: string, o: Offer, target: string, tripId?: string, userId?: string): Promise<string> {
  const u = new URL(`${origin}/affiliates/click`);
  u.searchParams.set("o", o.id);
  u.searchParams.set("p", o.sponsored ? "sponsor" : partnerName(o));
  u.searchParams.set("c", o.category);
  u.searchParams.set("to", target);
  if (tripId) u.searchParams.set("t", tripId);
  if (userId) u.searchParams.set("u", userId);
  u.searchParams.set("sig", await sign(env.AFFILIATE_SIGNING_KEY, canonical(u.searchParams)));
  return u.toString();
}

function partnerName(o: Offer): string {
  return o.category === "hotel" ? "booking" : o.category === "campsite" ? "hipcamp" : "osm";
}

function canonical(params: URLSearchParams): string {
  return [...params.entries()]
    .filter(([k]) => k !== "sig")
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Signed redirect: only links this Worker minted can be followed (no open redirect). */
async function click(url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const sig = url.searchParams.get("sig") ?? "";
  if (!(await verify(env.AFFILIATE_SIGNING_KEY, canonical(url.searchParams), sig))) {
    throw new HttpError(403, "bad_signature");
  }
  const target = new URL(url.searchParams.get("to")!);
  const clickId = crypto.randomUUID();
  // Sub-id so the partner's conversion report names our click.
  if (target.hostname.endsWith("booking.com")) target.searchParams.set("label", `convoy-${clickId}`);
  else target.searchParams.set("subid", clickId);

  const trip = url.searchParams.get("t");
  const user = url.searchParams.get("u");
  ctx.waitUntil(
    new Supabase(env)
      .upsert("affiliate_clicks", {
        id: clickId,
        offer_id: url.searchParams.get("o"),
        provider: url.searchParams.get("p"),
        category: url.searchParams.get("c"),
        trip_id: trip && UUID.test(trip) ? trip : null,
        user_id: user && UUID.test(user) ? user : null,
      })
      .catch((e) => console.error("click log failed", e)),
  );
  return Response.redirect(target.toString(), 302);
}

/**
 * Partner conversion callback. Partners are configured to POST
 * `{provider, click_id, external_ref, commission_cents, currency, status}`
 * with header `x-convoy-signature: HMAC(body)`.
 */
async function postback(req: Request, env: Env): Promise<Response> {
  const raw = await req.text();
  const sig = req.headers.get("x-convoy-signature") ?? "";
  if (!(await verify(env.AFFILIATE_SIGNING_KEY, raw, sig))) throw new HttpError(403, "bad_signature");
  let body: {
    provider?: string;
    click_id?: string;
    external_ref?: string;
    commission_cents?: number;
    currency?: string;
    status?: string;
  };
  try {
    body = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "invalid_json");
  }
  if (!body.provider || !body.external_ref) throw new HttpError(400, "missing_fields");
  const clickId = body.click_id?.replace(/^convoy-/, "");
  await new Supabase(env).upsert(
    "affiliate_conversions",
    {
      provider: body.provider,
      external_ref: body.external_ref,
      click_id: clickId && UUID.test(clickId) ? clickId : null,
      commission_cents: Math.max(0, Math.round(body.commission_cents ?? 0)),
      currency: (body.currency ?? "USD").slice(0, 3).toUpperCase(),
      status: ["pending", "confirmed", "cancelled"].includes(body.status ?? "") ? body.status : "pending",
    },
    "provider,external_ref",
  );
  return json({ ok: true });
}

// ───────────────────────────── sponsors ─────────────────────────────

async function sponsoredNear(env: Env, route: LatLng[], cats: Category[]): Promise<Offer[]> {
  const lats = route.map((p) => p[0]), lngs = route.map((p) => p[1]);
  const pad = 1; // degrees; refined by radius below
  const now = new Date().toISOString();
  const rows = await new Supabase(env)
    .select<{ id: string; partner_name: string; category: string; name: string; lat: number; lng: number; radius_km: number; url: string }>(
      "sponsored_placements",
      `select=id,partner_name,category,name,lat,lng,radius_km,url&active=is.true&starts_at=lte.${now}&or=(ends_at.is.null,ends_at.gt.${now})` +
        `&lat=gte.${Math.min(...lats) - pad}&lat=lte.${Math.max(...lats) + pad}&lng=gte.${Math.min(...lngs) - pad}&lng=lte.${Math.max(...lngs) + pad}`,
    )
    .catch(() => []);
  const out: Offer[] = [];
  for (const r of rows) {
    if (!cats.includes(r.category as Category)) continue;
    const { alongM, offM } = project(route, [r.lat, r.lng]);
    if (offM > r.radius_km * 1000) continue;
    out.push({
      id: `sponsor:${r.id}`,
      category: r.category as Category,
      name: r.name,
      lat: r.lat,
      lng: r.lng,
      provider: r.partner_name,
      detour_km: Math.round(offM / 100) / 10,
      along_km: Math.round(alongM / 100) / 10,
      booking_url: r.url,
      sponsored: true,
    });
  }
  return out;
}
