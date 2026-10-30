import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/env";
import type { LatLng } from "../src/geo";
import worker from "../src/index";
import { fcmMessage } from "../src/notify";
import { toPlace } from "../src/places";
import { plazasOnRoute } from "../src/tolls";
import { forecastAt, warningsFor } from "../src/weather";

const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
const kv = { get: async () => null, put: async () => {} } as unknown as KVNamespace;

describe("places", () => {
  it("turns Photon features into a name and a detail line", () => {
    const p = toPlace({
      geometry: { coordinates: [76.6552, 12.3052] },
      properties: { name: "Mysore Palace", city: "Mysuru", state: "Karnataka", country: "India", osm_key: "tourism", osm_value: "attraction" },
    })!;
    expect(p).toEqual({ name: "Mysore Palace", detail: "Mysuru, Karnataka, India", lat: 12.3052, lng: 76.6552, type: "tourism:attraction" });
  });

  it("falls back to the street for unnamed addresses and skips empty features", () => {
    expect(toPlace({ geometry: { coordinates: [77, 12] }, properties: { street: "MG Road", housenumber: "12", city: "Bengaluru" } })?.name).toBe("MG Road 12");
    expect(toPlace({ geometry: { coordinates: [77, 12] }, properties: {} })).toBeNull();
  });

  it("biases searches to the caller and validates the query", async () => {
    const fetchMock = vi.fn(async (_u: string) => Response.json({ features: [] }));
    vi.stubGlobal("fetch", fetchMock);
    const env = { CACHE: kv, PHOTON_URL: "https://photon.test" } as Env;
    const ok = await worker.fetch(new Request("https://edge/places/search?q=fuel&lat=12.97&lng=77.59"), env, ctx);
    expect(ok.status).toBe(200);
    expect(String(fetchMock.mock.calls[0][0])).toContain("lat=12.970&lon=77.590");
    const short = await worker.fetch(new Request("https://edge/places/search?q=a"), env, ctx);
    expect(short.status).toBe(400);
    vi.restoreAllMocks();
  });
});

describe("weather", () => {
  const hourly = {
    time: ["2026-11-01T05:00", "2026-11-01T06:00", "2026-11-01T07:00"],
    temperature_2m: [19, 20, 22],
    precipitation_probability: [10, 80, 20],
    precipitation: [0, 5.2, 0],
    visibility: [400, 9000, 20000],
    weather_code: [45, 63, 1],
    wind_gusts_10m: [10, 20, 65],
  };

  it("picks the hour nearest the planned arrival and flags what matters", () => {
    expect(forecastAt(hourly, new Date("2026-11-01T05:10:00Z"))!.warnings).toEqual(["fog"]);
    expect(forecastAt(hourly, new Date("2026-11-01T06:20:00Z"))!.warnings).toEqual(["heavy_rain"]);
    expect(forecastAt(hourly, new Date("2026-11-01T07:00:00Z"))!.warnings).toEqual(["wind"]);
  });

  it("returns null outside the forecast window", () => {
    expect(forecastAt(hourly, new Date("2026-11-05T07:00:00Z"))).toBeNull();
  });

  it("classifies storms, snow and light rain", () => {
    expect(warningsFor({ code: 95, precip_mm: 1, precip_prob: 90, visibility_m: 5000, gust_kmh: 30 })).toEqual(["storm", "rain"]);
    expect(warningsFor({ code: 73, precip_mm: 0.2, precip_prob: 30, visibility_m: 5000, gust_kmh: 10 })).toEqual(["snow"]);
    expect(warningsFor({ code: 61, precip_mm: 0.3, precip_prob: 40, visibility_m: 9000, gust_kmh: 10 })).toEqual(["rain"]);
    expect(warningsFor({ code: 1, precip_mm: 0, precip_prob: 5, visibility_m: 20000, gust_kmh: 10 })).toEqual([]);
  });
});

describe("tolls", () => {
  const route: LatLng[] = [
    [12.9, 77.5],
    [12.9, 77.9],
  ];

  it("keeps booths on the road, merges lanes of one plaza and orders them", () => {
    const plazas = plazasOnRoute(route, [
      { id: 3, lat: 12.9, lon: 77.8, tags: { name: "Plaza B" } },
      { id: 1, lat: 12.9002, lon: 77.6, tags: { name: "Plaza A" } },
      { id: 2, lat: 12.9001, lon: 77.6003 }, // another lane of Plaza A
      { id: 4, lat: 12.95, lon: 77.7 }, // 5 km off the road
    ]);
    expect(plazas.map((p) => p.name)).toEqual(["Plaza A", "Plaza B"]);
    expect(plazas[0].along_km).toBeCloseTo(10.8, 0);
  });
});

describe("notifications", () => {
  afterEach(() => vi.restoreAllMocks());

  it("requires a signed-in user", async () => {
    const res = await worker.fetch(new Request("https://edge/notify", { method: "POST", body: "{}" }), { CACHE: kv } as Env, ctx);
    expect(res.status).toBe(401);
  });

  it("marks SOS pushes urgent on their own channel", () => {
    const m = fcmMessage("tok", "sos", "SOS", "Ravi needs help", "trip-1");
    expect(m.android.priority).toBe("high");
    expect(m.android.notification.channel_id).toBe("sos");
    expect(fcmMessage("tok", "plan", "Plan", "x", "trip-1").android.notification.channel_id).toBe("convoy");
  });

  it("refuses SOS texts when SMS is not configured", async () => {
    const res = await worker.fetch(new Request("https://edge/sos/sms", { method: "POST", body: "{}" }), { CACHE: kv } as Env, ctx);
    expect(res.status).toBe(401);
  });
});

describe("invite links", () => {
  it("serves a landing page with the code and an app deep link", async () => {
    const res = await worker.fetch(new Request("https://edge/j/k7q2m9xp"), { PLAY_STORE_URL: "https://play.test/app" } as Env, ctx);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("K7Q2M9XP");
    expect(html).toContain("drivesync://join/K7Q2M9XP");
    expect(html).toContain("https://play.test/app");
  });

  it("publishes Android app links only when configured", async () => {
    const empty = await worker.fetch(new Request("https://edge/.well-known/assetlinks.json"), {} as Env, ctx);
    expect(await empty.json()).toEqual([]);
    const env = { ANDROID_PACKAGE_NAME: "com.example.drivesync", ANDROID_CERT_SHA256: "AA:BB" } as Env;
    const res = await worker.fetch(new Request("https://edge/.well-known/assetlinks.json"), env, ctx);
    const body = (await res.json()) as { target: { package_name: string; sha256_cert_fingerprints: string[] } }[];
    expect(body[0].target.package_name).toBe("com.example.drivesync");
    expect(body[0].target.sha256_cert_fingerprints).toEqual(["AA:BB"]);
  });
});

