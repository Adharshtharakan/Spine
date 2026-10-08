#!/usr/bin/env bash
# Cut a regional basemap out of the Protomaps daily planet build and upload it
# to R2, where the Worker serves it as XYZ tiles.
#
#   ./build_region.sh <name> <minLon,minLat,maxLon,maxLat> [maxzoom]
#   ./build_region.sh india 68.1,6.5,97.4,35.7 14
#
# Requires: pmtiles CLI (https://github.com/protomaps/go-pmtiles/releases),
# wrangler (npm i -g wrangler), and an R2 bucket named convoy-tiles.
set -euo pipefail

NAME=${1:?region name}
BBOX=${2:?minLon,minLat,maxLon,maxLat}
MAXZOOM=${3:-14}
BUILD=${PROTOMAPS_BUILD:-$(date -u -d 'yesterday' +%Y%m%d 2>/dev/null || date -u -v-1d +%Y%m%d)}
SRC="https://build.protomaps.com/${BUILD}.pmtiles"
OUT="${NAME}.pmtiles"

echo "Extracting ${BBOX} (z0-${MAXZOOM}) from ${SRC}"
# extract only range-reads the parts of the planet it needs.
pmtiles extract "$SRC" "$OUT" --bbox="$BBOX" --maxzoom="$MAXZOOM"
pmtiles show "$OUT" | head -20

echo "Uploading to R2 as basemap/convoy.pmtiles"
wrangler r2 object put "convoy-tiles/basemap/convoy.pmtiles" --file "$OUT" --remote

if [[ "${MIRROR_ASSETS:-1}" == "1" ]]; then
  echo "Mirroring fonts and sprites into R2 (assets/)"
  tmp=$(mktemp -d)
  git clone --depth 1 https://github.com/protomaps/basemaps-assets "$tmp/assets"
  (cd "$tmp/assets" && find fonts sprites -type f) | while read -r f; do
    wrangler r2 object put "convoy-tiles/assets/$f" --file "$tmp/assets/$f" --remote >/dev/null
  done
  rm -rf "$tmp"
fi
echo "Done."
