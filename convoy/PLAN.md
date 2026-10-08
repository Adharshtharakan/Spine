# Convoy Coordination Platform — Build Plan

Source: *Executive Business Synopsis — Convoy Coordination Platform* (Angith, 8 Sep 2026).

Convoy is a consumer micro-fleet tool for group travel across several vehicles.
This plan maps every feature in the synopsis to a component and builds them in
the six steps the brief requires. Each step lands as its own commit.

## Feature → component map

| Feature (synopsis) | Client (Flutter) | Backend |
|---|---|---|
| Collaborative dynamic itineraries | `sync/itinerary_doc.dart` (HLC last-writer-wins CRDT, fractional ordering, schedule shift), `features/itinerary` | `waypoints` table, `hlc` guard trigger, Realtime `postgres_changes` |
| Live group tracking + lead vehicle identification | `services/location`, `services/tracking/lead_vehicle.dart`, `features/map` | Realtime broadcast `trip:<id>` (ephemeral), `member_locations` last-known upsert |
| Localized text + push-to-talk voice | `features/chat`, `services/voice/ptt_service.dart` (WebRTC mesh, floor control) | `messages` table (RLS per party), Realtime broadcast for WebRTC signalling only — media stays P2P |
| Offline resiliency | `services/offline/offline_maps.dart` (bounding-box tile packs), `services/tracking/dead_reckoning.dart`, `services/offline/outbox.dart`, `services/offline/trip_cache.dart` | Self-hosted PMTiles served as XYZ by the Worker (`/tiles`) |
| Offline mesh fallback | `services/mesh` (Nearby Connections on Android, MultipeerConnectivity on iOS, compact binary GPS codec, TTL relay) | — |
| Public trip discovery + mutual acceptance | `features/discovery`, `features/guidelines` | `guideline_documents`, `guideline_acceptances`, `join_requests`, `request_to_join` + `decide_join_request` RPCs, Worker `/discovery/*` |
| Freemium subscription | `services/billing`, `features/paywall` | `entitlements`, vehicle-cap trigger, Worker `/billing/verify` (Google Play + App Store Server API) |
| B2B affiliate bookings (hotels, campsites, fuel, rest areas) + sponsored stops | `features/stops` | Worker `/affiliates/along-route`, `/affiliates/click`, `/affiliates/postback`; `affiliate_clicks`, `affiliate_conversions`, `sponsored_placements` |

## Sequenced steps

1. **Mobile app initialisation** — Flutter (single iOS/Android codebase), Riverpod
   for state. Domain models, the itinerary CRDT and geo maths are pure Dart with
   unit tests.
2. **Mapping + offline** — `maplibre_gl` (MapLibre Native). Protomaps basemap
   from a self-hosted PMTiles archive in Cloudflare R2, served as `/{z}/{x}/{y}.mvt`
   by the Worker so MapLibre's offline-region downloader can cache bounding boxes
   along the route. Hardware GPS (`geolocator`) keeps plotting with no network.
3. **Supabase** — schema, RLS on every table (party isolation via
   `is_trip_member()`), guideline versions, mutual acceptance, entitlements,
   Realtime authorisation on private `trip:<id>` channels.
4. **Realtime + voice** — positions over Realtime broadcast (no DB write per fix),
   chat and itinerary over `postgres_changes`, WebRTC full-mesh PTT with
   signalling over the same private channel.
5. **Offline mesh** — custom platform channel `convoy/mesh`: Nearby Connections
   (`P2P_CLUSTER`) on Android, MultipeerConnectivity on iOS. 40-byte position
   frames, relayed with TTL and de-duplication.
6. **Edge functions** — one Cloudflare Worker: tiles, discovery, affiliates,
   billing verification. No idle servers.

## Cost posture

- Positions never touch Postgres per fix: broadcast only, last-known upserted
  every 30 s.
- Voice is P2P (STUN only by default; TURN optional).
- Tiles: one PMTiles file in R2 (no egress fees), Worker + edge cache in front.
- POIs for fuel / rest areas / campsites come from OpenStreetMap (Overpass),
  cached in Workers KV; paid partner APIs are adapters behind env flags.
