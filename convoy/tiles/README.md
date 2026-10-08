# Basemap tiles

Convoy uses royalty-free vector tiles: a [Protomaps](https://protomaps.com)
basemap (OpenStreetMap data) stored as one PMTiles file in Cloudflare R2.

```
R2: convoy-tiles/basemap/convoy.pmtiles   ← range-read by the Worker
Worker: /style.json, /tiles/{z}/{x}/{y}.mvt, /fonts/…, /sprites/…
App:   MapLibre Native → style.json → tiles (online)
                       → offline region DB (bounding boxes along the route)
```

Why the Worker sits in front of the archive instead of the app reading
`pmtiles://` directly: MapLibre Native's offline-region downloader enumerates
tiles by `{z}/{x}/{y}` URL. Serving XYZ keeps offline packs working on both
platforms, and the edge cache means each tile is read from R2 once per
location.

## Build a region

```bash
./build_region.sh india 68.1,6.5,97.4,35.7 14
```

A national extract at z14 is typically 1–5 GB. R2 charges for storage only;
egress is free.

## Offline packs on the device

`OfflineMapService` (app) splits the route into ~60 km boxes padded by 8 km
and downloads z5–z14 for each box (z5–z12 on the free tier). Once cached, the
map renders without any network, and the phone's GPS keeps plotting the
vehicle because satellite positioning never needed the cellular network.
