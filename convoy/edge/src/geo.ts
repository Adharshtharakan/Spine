export type LatLng = [number, number]; // [lat, lng]

const R = 6371008.8;
const rad = (d: number) => (d * Math.PI) / 180;

export function distanceM(a: LatLng, b: LatLng): number {
  const dLat = rad(b[0] - a[0]);
  const dLng = rad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Distance along [route] to the closest point to [p], and how far off it [p] is. */
export function project(route: LatLng[], p: LatLng): { alongM: number; offM: number } {
  let best = { alongM: 0, offM: Infinity };
  let walked = 0;
  for (let i = 0; i < route.length - 1; i++) {
    const a = route[i], b = route[i + 1];
    const seg = distanceM(a, b);
    const cos = Math.cos(rad((a[0] + b[0]) / 2));
    const ax = a[1] * cos, ay = a[0], bx = b[1] * cos, by = b[0], px = p[1] * cos, py = p[0];
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
    const q: LatLng = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    const off = distanceM(q, p);
    if (off < best.offM) best = { alongM: walked + seg * t, offM: off };
    walked += seg;
  }
  if (route.length === 1) best = { alongM: 0, offM: distanceM(route[0], p) };
  return best;
}

export interface BBox {
  south: number;
  west: number;
  north: number;
  east: number;
}

export function bboxAround(points: LatLng[], padM: number): BBox {
  let s = 90, n = -90, w = 180, e = -180;
  for (const [lat, lng] of points) {
    s = Math.min(s, lat); n = Math.max(n, lat);
    w = Math.min(w, lng); e = Math.max(e, lng);
  }
  const dLat = padM / 111320;
  const dLng = padM / (111320 * Math.max(0.01, Math.cos(rad((s + n) / 2))));
  return { south: s - dLat, north: n + dLat, west: w - dLng, east: e + dLng };
}

/** Splits a long route into boxes of at most [maxSpanM] so each Overpass query stays small. */
export function corridor(route: LatLng[], maxSpanM: number, padM: number): BBox[] {
  if (route.length === 0) return [];
  const out: BBox[] = [];
  let chunk: LatLng[] = [route[0]];
  for (const p of route.slice(1)) {
    chunk.push(p);
    const b = bboxAround(chunk, 0);
    if (distanceM([b.south, b.west], [b.north, b.east]) >= maxSpanM) {
      out.push(bboxAround(chunk, padM));
      chunk = [p];
    }
  }
  if (chunk.length > 1 || out.length === 0) out.push(bboxAround(chunk, padM));
  return out;
}

/** Thins a dense route so request bodies and corridor math stay cheap. */
export function simplify(route: LatLng[], minStepM: number): LatLng[] {
  if (route.length < 3) return route;
  const out: LatLng[] = [route[0]];
  for (const p of route.slice(1, -1)) {
    if (distanceM(out[out.length - 1], p) >= minStepM) out.push(p);
  }
  out.push(route[route.length - 1]);
  return out;
}
