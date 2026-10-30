import type { Env } from "./env";
import { HttpError, json, readJson } from "./http";

/**
 *   POST /weather { points: [{ lat, lng, at }] } → forecast at each stop's ETA
 *
 * One Open-Meteo request for up to 30 stops (it accepts lists of
 * coordinates). For each point the hour nearest its planned arrival is
 * returned with plain warnings the app can show and speak: rain, heavy rain,
 * fog, storm, snow, strong wind. Points beyond the 16-day forecast come back
 * as null. Cached for an hour per rounded point set.
 */
export async function handleWeather(req: Request, env: Env, ctx: ExecutionContext): Promise<Response | null> {
  if (req.method !== "POST" || new URL(req.url).pathname !== "/weather") return null;
  const body = await readJson<{ points?: { lat: number; lng: number; at: string }[] }>(req);
  const points = (body.points ?? []).filter(
    (p) => Math.abs(p?.lat) <= 90 && Math.abs(p?.lng) <= 180 && !Number.isNaN(Date.parse(p?.at)),
  );
  if (points.length === 0) throw new HttpError(400, "no_points");
  if (points.length > 30) throw new HttpError(400, "too_many_points");

  const lat = points.map((p) => p.lat.toFixed(2)).join(",");
  const lng = points.map((p) => p.lng.toFixed(2)).join(",");
  const key = `wx:v1:${lat}:${lng}:${new Date().toISOString().slice(0, 13)}`;
  let series = await env.CACHE.get<HourlySeries[]>(key, "json");
  if (!series) {
    const base = env.OPEN_METEO_URL ?? "https://api.open-meteo.com";
    const params = new URLSearchParams({
      latitude: lat,
      longitude: lng,
      hourly: "temperature_2m,precipitation_probability,precipitation,visibility,weather_code,wind_gusts_10m",
      timezone: "GMT",
      forecast_days: "16",
    });
    const res = await fetch(`${base}/v1/forecast?${params}`, { headers: { "user-agent": "convoy-edge/1.0" } });
    if (!res.ok) throw new HttpError(502, "weather_unavailable");
    const data = (await res.json()) as { hourly: HourlySeries } | { hourly: HourlySeries }[];
    series = (Array.isArray(data) ? data : [data]).map((d) => d.hourly);
    ctx.waitUntil(env.CACHE.put(key, JSON.stringify(series), { expirationTtl: 60 * 60 }));
  }
  return json({ forecasts: points.map((p, i) => forecastAt(series![i] ?? series![0], new Date(p.at))) });
}

export interface HourlySeries {
  time: string[];
  temperature_2m: (number | null)[];
  precipitation_probability: (number | null)[];
  precipitation: (number | null)[];
  visibility: (number | null)[];
  weather_code: (number | null)[];
  wind_gusts_10m: (number | null)[];
}

export interface Forecast {
  at: string;
  temp_c: number | null;
  precip_prob: number | null;
  precip_mm: number | null;
  visibility_m: number | null;
  code: number | null;
  gust_kmh: number | null;
  warnings: Warning[];
}

export type Warning = "storm" | "heavy_rain" | "rain" | "fog" | "snow" | "wind";

export function forecastAt(h: HourlySeries | undefined, at: Date): Forecast | null {
  if (!h?.time?.length) return null;
  const target = at.getTime();
  let best = -1;
  let bestGap = Infinity;
  h.time.forEach((t, i) => {
    const gap = Math.abs(Date.parse(`${t}:00Z`) - target);
    if (gap < bestGap) {
      bestGap = gap;
      best = i;
    }
  });
  // Outside the forecast window (more than 90 minutes from any hour).
  if (best < 0 || bestGap > 90 * 60 * 1000) return null;
  const f: Forecast = {
    at: `${h.time[best]}:00Z`,
    temp_c: h.temperature_2m[best],
    precip_prob: h.precipitation_probability[best],
    precip_mm: h.precipitation[best],
    visibility_m: h.visibility[best],
    code: h.weather_code[best],
    gust_kmh: h.wind_gusts_10m[best],
    warnings: [],
  };
  f.warnings = warningsFor(f);
  return f;
}

/** WMO weather codes and thresholds that matter to someone driving. */
export function warningsFor(f: Pick<Forecast, "precip_prob" | "precip_mm" | "visibility_m" | "code" | "gust_kmh">): Warning[] {
  const w: Warning[] = [];
  const code = f.code ?? -1;
  if (code >= 95) w.push("storm");
  if ((f.precip_mm ?? 0) >= 4 || [65, 67, 82].includes(code)) w.push("heavy_rain");
  else if ((f.precip_prob ?? 0) >= 60 || (f.precip_mm ?? 0) >= 0.5 || (code >= 51 && code <= 67) || code === 80 || code === 81) {
    w.push("rain");
  }
  if ((f.visibility_m ?? Infinity) < 1000 || code === 45 || code === 48) w.push("fog");
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) w.push("snow");
  if ((f.gust_kmh ?? 0) >= 60) w.push("wind");
  return w;
}
