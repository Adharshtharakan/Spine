import { afterEach, describe, expect, it, vi } from "vitest";
import { categorize, partnerUrl, toOffer } from "../src/affiliates";
import type { Env } from "../src/env";
import { corridor, distanceM, type LatLng, project, simplify } from "../src/geo";
import { sign, verify } from "../src/sign";
import worker from "../src/index";

const route: LatLng[] = [
  [0, 0],
  [0, 1],
  [0, 2],
];

describe("geo", () => {
  it("measures distance and progress along a route", () => {
    expect(distanceM([0, 0], [0, 1])).toBeCloseTo(111195, -2);
    const p = project(route, [0.01, 1.5]);
    expect(p.alongM).toBeCloseTo(111195 * 1.5, -3);
    expect(p.offM).toBeCloseTo(1112, -1);
  });

  it("splits long routes into corridor boxes that cover the route", () => {
    const boxes = corridor(route, 80_000, 5_000);
    expect(boxes.length).toBeGreaterThan(1);
    for (const [lat, lng] of route) {
      expect(boxes.some((b) => lat >= b.south && lat <= b.north && lng >= b.west && lng <= b.east)).toBe(true);
    }
  });

  it("simplifies dense routes but keeps the ends", () => {
    const dense: LatLng[] = Array.from({ length: 1000 }, (_, i) => [0, i / 1000]);
    const s = simplify(dense, 5_000);
    expect(s.length).toBeLessThan(40);
    expect(s[0]).toEqual(dense[0]);
    expect(s[s.length - 1]).toEqual(dense[999]);
  });
});

describe("affiliate offers", () => {
  it("categorises OSM tags", () => {
    expect(categorize({ amenity: "fuel" })).toBe("fuel");
    expect(categorize({ highway: "rest_area" })).toBe("rest_area");
    expect(categorize({ tourism: "motel" })).toBe("hotel");
    expect(categorize({ tourism: "caravan_site" })).toBe("campsite");
    expect(categorize({ shop: "bakery" })).toBeNull();
  });

  it("keeps fuel near the road and drops far detours", () => {
    const near = toOffer({ type: "node", id: 1, lat: 0.005, lon: 0.5, tags: { amenity: "fuel", brand: "Shell" } }, route);
    expect(near?.category).toBe("fuel");
    expect(near?.name).toBe("Shell");
    expect(near?.along_km).toBeCloseTo(55.6, 0);
    const far = toOffer({ type: "node", id: 2, lat: 0.1, lon: 0.5, tags: { amenity: "fuel" } }, route);
    expect(far).toBeNull();
  });

  it("only builds partner links for configured programmes", () => {
    const hotel = toOffer({ type: "node", id: 3, lat: 0.01, lon: 1, tags: { tourism: "hotel", name: "Inn" } }, route)!;
    expect(partnerUrl({} as Env, hotel)).toBeNull();
    const url = partnerUrl({ BOOKING_AFFILIATE_ID: "123" } as Env, hotel)!;
    expect(new URL(url).searchParams.get("aid")).toBe("123");
  });
});

describe("signing", () => {
  it("verifies its own signatures and rejects tampering", async () => {
    const s = await sign("k", "a=1&b=2");
    expect(await verify("k", "a=1&b=2", s)).toBe(true);
    expect(await verify("k", "a=1&b=3", s)).toBe(false);
    expect(await verify("other", "a=1&b=2", s)).toBe(false);
  });
});

describe("worker routes", () => {
  const env = { AFFILIATE_SIGNING_KEY: "secret", SUPABASE_URL: "https://x.supabase.co" } as Env;
  const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
  afterEach(() => vi.restoreAllMocks());

  it("refuses unsigned click redirects (no open redirect)", async () => {
    const res = await worker.fetch(new Request("https://edge/affiliates/click?to=https://evil.example&sig=x"), env, ctx);
    expect(res.status).toBe(403);
  });

  it("follows signed click links and tags the partner URL", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("[]", { status: 201 })));
    const params = new URLSearchParams({ c: "hotel", o: "osm:node/1", p: "booking", to: "https://www.booking.com/searchresults.html?aid=1" });
    const canonical = [...params.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join("&");
    params.set("sig", await sign("secret", canonical));
    const res = await worker.fetch(new Request(`https://edge/affiliates/click?${params}`), env, ctx);
    expect(res.status).toBe(302);
    expect(new URL(res.headers.get("location")!).searchParams.get("label")).toMatch(/^convoy-/);
  });

  it("rejects unsigned partner postbacks", async () => {
    const res = await worker.fetch(
      new Request("https://edge/affiliates/postback", { method: "POST", body: "{}", headers: { "x-convoy-signature": "nope" } }),
      env,
      ctx,
    );
    expect(res.status).toBe(403);
  });

  it("requires a user token to request joining a trip", async () => {
    const res = await worker.fetch(
      new Request("https://edge/discovery/trips/7cba5322-6ff2-40c6-9a10-5720dc911c3c/join", { method: "POST", body: "{}" }),
      env,
      ctx,
    );
    expect(res.status).toBe(401);
  });

  it("requires a user token to verify purchases", async () => {
    const res = await worker.fetch(new Request("https://edge/billing/verify", { method: "POST", body: "{}" }), env, ctx);
    expect(res.status).toBe(401);
  });
});
