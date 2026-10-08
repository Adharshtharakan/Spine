# Convoy

A coordination platform for group trips with several vehicles: one shared
plan, one live map, one private channel for every car in the party, even
where there is no cell signal.

| | |
|---|---|
| `app/` | Flutter app (iOS + Android) |
| `supabase/` | Postgres schema, RLS, RPCs, seed, rule tests |
| `edge/` | Cloudflare Worker: map tiles, road routing, discovery, affiliates, billing |
| `tiles/` | Script to build and upload the self-hosted Protomaps basemap |
| `PLAN.md` | Feature → component map and the build sequence |
| `SETUP.md` | **Step-by-step setup: Supabase, map, Worker, running in Android Studio** |

## What it does

- **Shared itinerary.** Waypoints, rest stops, destination changes and
  schedule shifts ("running 40 min late") sync to every driver. Edits are
  a CRDT (hybrid-logical-clock last-writer-wins with tombstones), so edits
  made offline merge correctly when the phone reconnects.
- **Live tracking + lead vehicle.** Every car on one map, about once per
  second. The organiser designates a lead. If the lead goes silent, the
  car furthest along the route is shown as lead. Standings show each car's
  gap to the lead and flag anyone off route.
- **Party-only text and push-to-talk.** Chat is visible to trip members
  only (RLS). Voice is half-duplex push-to-talk over peer-to-peer WebRTC,
  so no media server is involved.
- **Offline resiliency: last-resort prediction.** When nothing can reach
  a car, each phone estimates where it is from what it already had, with
  no data exchanged during the outage. It uses the car's last reported
  location (GPS, or a coarser cell-tower fix whose wider uncertainty is
  carried forward), its average moving speed (saved with the trip), and
  the cached road route with each leg's expected driving speed. It also
  holds a car at a planned stop until its departure time, and keeps a
  silent car at its last gap behind a convoy-mate that is still
  reporting. The estimate is drawn with a growing uncertainty halo and a
  plain-language reason ("moving with Blue Jeep", "probably at Dhaba
  until 14:30"). Offline map packs and the GPS keep your own position
  exact, and writes queue in an outbox.
- **Optional off-grid links.** With weak signal, the app polls over HTTP
  every 15 s. With no signal, cars with a paired Meshtastic LoRa radio
  (2–10 km car to car, relayed between radios) keep sharing encrypted
  positions and chat, and any car with signal acts as a gateway.
  Phone-to-phone Bluetooth/Wi-Fi covers cars that are bunched together.
- **Public trip discovery.** Verified organisers (confirmed phone plus
  current terms) publish trips. A traveller accepts the guidelines and
  driver terms (licensed, insured, roadworthy) and requests to join; the
  organiser accepts. Both sides' accepted versions are recorded.
- **Revenue.** Free covers 2 vehicles per trip and one trip of overview
  offline maps. Premium covers 25 vehicles, street-level offline maps for
  any number of trips, and multi-hop mesh. Purchases are verified
  server-side with Google and Apple. Hotels, campsites, fuel and rest
  areas along the route link to partners through signed, tracked links
  with conversion postbacks. Sponsored stops from tourism boards and
  highway businesses appear in Discover and along routes.

## Cost profile

- No servers to run. Supabase handles auth, Postgres and Realtime. One
  Cloudflare Worker handles everything else and scales to zero.
- Positions never hit Postgres per fix: they go over Realtime broadcast,
  with one last-known upsert every 30 s.
- Voice is peer-to-peer. TURN is optional.
- Tiles are one PMTiles file in R2 (no egress fees) behind the edge cache.
- Points of interest come from OpenStreetMap via Overpass, cached in KV for
  a week.

## Setup

New to the project? Follow **[SETUP.md](SETUP.md)**. It covers everything
from installing Flutter to running on your phone. The short version:

### 1. Supabase

```bash
supabase link --project-ref <ref>
supabase db push          # applies supabase/migrations
psql "$DATABASE_URL" -f supabase/seed.sql
```

In the dashboard: enable the **Email** provider (OTP) and the **Phone**
provider (an SMS provider is needed for organiser verification), and make
sure Realtime is on.

### 2. Basemap

```bash
cd tiles && ./build_region.sh india 68.1,6.5,97.4,35.7 14
```

### 3. Worker

```bash
cd edge
npm ci
wrangler kv namespace create CACHE      # put the id in wrangler.toml
wrangler r2 bucket create convoy-tiles
# set SUPABASE_URL / SUPABASE_ANON_KEY in wrangler.toml, then:
wrangler secret put SUPABASE_SERVICE_ROLE_KEY
wrangler secret put AFFILIATE_SIGNING_KEY
# optional: SUPABASE_JWT_SECRET (legacy HS256 projects), BOOKING_AFFILIATE_ID,
# HIPCAMP_AFFILIATE_ID, GOOGLE_SERVICE_ACCOUNT_JSON, ANDROID_PACKAGE_NAME,
# APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_BUNDLE_ID
npm run deploy
```

`OSRM_URL` (road geometry for prediction) defaults to the public OSRM demo
server, which is for development only; self-host OSRM for production.

Store notifications: point App Store Server Notifications V2 at
`/billing/apple/notify`, and the Play RTDN Pub/Sub push subscription at
`/billing/google/rtdn`.

### 4. App

```bash
cd app
cp env.example.json env.json   # fill in Supabase + Worker URLs
flutter pub get
flutter run --dart-define-from-file=env.json
```

Create the subscription products `convoy_premium_monthly` and
`convoy_premium_yearly` in Play Console and App Store Connect.

## Tests

```bash
cd app && flutter test                  # sync CRDT, geo, lead, dead reckoning, mesh, floor control
cd edge && npm test                     # geo, offers, signing, route guards
PGHOST=… PGUSER=… supabase/tests/run.sh # RLS isolation, mutual acceptance, vehicle cap, HLC guard
```

CI runs all three (`.github/workflows/ci.yml`).
