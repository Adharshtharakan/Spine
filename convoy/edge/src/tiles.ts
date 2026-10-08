import { layers, namedFlavor } from "@protomaps/basemaps";
import { PMTiles, type RangeResponse, type Source, TileType } from "pmtiles";
import type { Env } from "./env";
import { corsHeaders, HttpError, json } from "./http";

/**
 * Serves a self-hosted Protomaps PMTiles archive (a single file in R2) as
 * ordinary `{z}/{x}/{y}` vector tiles. MapLibre Native's offline downloader
 * needs plain tile URLs to enumerate a bounding box, so the archive is never
 * exposed directly; the Worker range-reads it and the edge cache absorbs
 * repeat requests. R2 has no egress fees, so the whole basemap costs storage
 * plus Worker invocations.
 */
class R2Source implements Source {
  constructor(
    private bucket: R2Bucket,
    private key: string,
  ) {}

  getKey() {
    return this.key;
  }

  async getBytes(offset: number, length: number, _signal?: AbortSignal, etag?: string): Promise<RangeResponse> {
    const obj = await this.bucket.get(this.key, {
      range: { offset, length },
      onlyIf: etag ? { etagMatches: etag } : undefined,
    });
    if (!obj) throw new HttpError(404, "archive_missing");
    if (!("body" in obj)) throw new Error("etag_mismatch");
    return { data: await obj.arrayBuffer(), etag: obj.etag };
  }
}

// Module scope survives between requests on a warm isolate, so the archive
// header and directories are fetched once per isolate, not per tile.
let archive: { key: string; pm: PMTiles } | undefined;

function getArchive(env: Env): PMTiles {
  if (!archive || archive.key !== env.PMTILES_KEY) {
    archive = { key: env.PMTILES_KEY, pm: new PMTiles(new R2Source(env.TILES, env.PMTILES_KEY)) };
  }
  return archive.pm;
}

const TILE_RE = /^\/tiles\/(\d+)\/(\d+)\/(\d+)\.(mvt|pbf|png|jpg|webp)$/;

export async function handleTiles(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (path === "/style.json") return styleJson(url, env);
  if (path === "/tiles.json") return tileJson(url, env);
  if (path.startsWith("/fonts/") || path.startsWith("/sprites/")) return staticAsset(req, env, ctx);

  const m = TILE_RE.exec(path);
  if (!m) return null;

  const cache = caches.default;
  const cached = await cache.match(req);
  if (cached) return cached;

  const [z, x, y] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (z > 22 || x >= 2 ** z || y >= 2 ** z) throw new HttpError(400, "bad_tile");

  const pm = getArchive(env);
  const header = await pm.getHeader();
  if (z < header.minZoom || z > header.maxZoom) {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  const tile = await pm.getZxy(z, x, y);
  if (!tile) return new Response(null, { status: 204, headers: { ...corsHeaders, "cache-control": "public, max-age=86400" } });

  const res = new Response(tile.data, {
    headers: {
      ...corsHeaders,
      "content-type": contentType(header.tileType),
      "cache-control": "public, max-age=86400, stale-while-revalidate=604800",
    },
  });
  ctx.waitUntil(cache.put(req, res.clone()));
  return res;
}

function contentType(t: TileType): string {
  switch (t) {
    case TileType.Mvt:
      return "application/x-protobuf";
    case TileType.Png:
      return "image/png";
    case TileType.Jpeg:
      return "image/jpeg";
    case TileType.Webp:
      return "image/webp";
    default:
      return "application/octet-stream";
  }
}

async function tileJson(url: URL, env: Env): Promise<Response> {
  const h = await getArchive(env).getHeader();
  return json(
    {
      tilejson: "3.0.0",
      tiles: [`${url.origin}/tiles/{z}/{x}/{y}.mvt`],
      minzoom: h.minZoom,
      maxzoom: h.maxZoom,
      bounds: [h.minLon, h.minLat, h.maxLon, h.maxLat],
      center: [h.centerLon, h.centerLat, h.centerZoom],
      attribution: ATTRIBUTION,
    },
    { headers: { "cache-control": "public, max-age=3600" } },
  );
}

const ATTRIBUTION =
  '<a href="https://protomaps.com">Protomaps</a> © <a href="https://openstreetmap.org/copyright">OpenStreetMap</a>';

/** MapLibre style built from the Protomaps basemap layers. `?theme=dark` for night driving. */
async function styleJson(url: URL, env: Env): Promise<Response> {
  const theme = url.searchParams.get("theme") === "dark" ? "dark" : "light";
  const lang = url.searchParams.get("lang") ?? "en";
  const h = await getArchive(env).getHeader();
  const style = {
    version: 8,
    name: `Convoy ${theme}`,
    glyphs: `${url.origin}/fonts/{fontstack}/{range}.pbf`,
    sprite: `${url.origin}/sprites/v4/${theme}`,
    sources: {
      protomaps: {
        type: "vector",
        tiles: [`${url.origin}/tiles/{z}/{x}/{y}.mvt`],
        minzoom: h.minZoom,
        maxzoom: h.maxZoom,
        attribution: ATTRIBUTION,
      },
    },
    layers: layers("protomaps", namedFlavor(theme), { lang }),
  };
  return json(style, { headers: { "cache-control": "public, max-age=3600" } });
}

/**
 * Fonts and sprites: mirrored in R2 under `assets/` when uploaded (see
 * tiles/README.md), otherwise fetched once from the public Protomaps assets
 * and cached at the edge. Offline packs download these too.
 */
async function staticAsset(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const cache = caches.default;
  const hit = await cache.match(req);
  if (hit) return hit;

  const path = decodeURIComponent(new URL(req.url).pathname).replace(/^\/+/, "");
  if (path.includes("..")) throw new HttpError(400, "bad_path");

  const type = path.endsWith(".png") ? "image/png" : path.endsWith(".json") ? "application/json" : "application/x-protobuf";
  let body: ArrayBuffer | null = null;
  const obj = await env.TILES.get(`assets/${path}`);
  if (obj) {
    body = await obj.arrayBuffer();
  } else {
    const base = env.ASSETS_FALLBACK_URL ?? "https://protomaps.github.io/basemaps-assets";
    const upstream = await fetch(`${base}/${path}`);
    if (!upstream.ok) return new Response(null, { status: upstream.status, headers: corsHeaders });
    body = await upstream.arrayBuffer();
  }
  const res = new Response(body, {
    headers: { ...corsHeaders, "content-type": type, "cache-control": "public, max-age=604800" },
  });
  ctx.waitUntil(cache.put(req, res.clone()));
  return res;
}
