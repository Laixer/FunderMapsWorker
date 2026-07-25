# FunderMaps tileserver (Martin)

Dynamic vector tileserver for FunderMaps, built on [Martin](https://github.com/maplibre/martin).
Serves building foundation tiles straight from PostGIS instead of the nightly
tippecanoe → Spaces batch pipeline (hybrid rollout: dynamic first for the
building layers, static pipeline stays as fallback).

## How it works

```
mapbox-gl (WebFront) ──▶ tiles.fundermaps.com/buildings/{z}/{x}/{y}
                              │ Martin (this repo, App Platform)
                              │   in-memory cache, 512 MB
                              ▼ cache miss only
                     maplayer.buildings(z,x,y)          ── MVT encode
                              ▼
                     maplayer.building_tiles            ── flat table,
                     (rebuilt nightly by the Windmill flow
                      f/fundermaps/data/refresh_data_model,
                      SQL owned by FunderMapsWorker)
```

- **z12–13** are served from a simplified geometry column (`geom_simple`,
  ~3 m tolerance), **z14–16** from full detail. Below z12: empty tiles.
- The attribute set equals the union of what the five tile-generating
  `maplayer.analysis_*` views expose in the public static tiles today.
- The MVT layer name inside every tile is `buildings`.

## Layout

This directory is deployment config only — pinned Martin image +
`config.yaml`. The DO App Platform app `fundermaps-tiles-prod` builds from
this repo with `source_dir: /tileserver`. All SQL (table, refresh procedure,
function source) lives in `sql/model/create_building_tiles.sql`; the nightly
rebuild (`CALL maplayer.refresh_building_tiles()`) runs from the Windmill
flow `f/fundermaps/data/refresh_data_model`.

## Database access

Connects as `fundermaps_tileserver`: read-only (SELECT on
`maplayer.building_tiles`, EXECUTE on `maplayer.buildings`), CONNECTION
LIMIT 5, `statement_timeout=15s`. `DATABASE_URL` is an App Platform secret;
Martin's `pool_size` (4) must stay below the role's connection limit.

## Testing a tile

```bash
curl -sI https://tiles.fundermaps.com/buildings/14/8415/5384   # Amsterdam
curl -s  https://tiles.fundermaps.com/catalog | jq
```

Frontend A/B testing without a deploy: the WebFront tileserver-test harness
(`TILESERVER_SOURCE` / `TILESERVER_LAYER` in localStorage or `?source=&layer=`
query params) can point the map at this server; the source-layer is `buildings`.

## Basemap style (MapLibre migration)

`styles/fundermaps-basemap.json` is the MapLibre basemap style for the
Mapbox → MapLibre migration: the legacy Studio style `fundermaps_basemap`
(warm tan monochrome) recreated on OpenFreeMap's Positron skeleton
(OpenMapTiles schema). It is generated — edit the palette/overrides in
`styles/build_style.py` and rerun it; don't hand-edit the JSON.

Tiles come from OpenFreeMap (self-hostable escape hatch if ever needed).
Everything else a browser fetches is served by Martin itself: the style at
`/style/fundermaps-basemap` (baked into the image from `styles/`), glyphs
at `/font/{fontstack}/{range}` (generated from Noto Sans TTFs, see
Dockerfile). This is deliberate: Chrome's Local Network Access feature
blocks fetches from public origins to `*.digitaloceanspaces.com` (both
the direct and CDN endpoints), so Spaces can never host browser-fetched
assets. No sprite currently (only road shields used it; Martin SVG
sprites are the follow-up if we want them back).
The purple municipality/district/neighborhood lines come from the Martin
function source `maplayer.boundaries` (`sql/model/create_boundary_tiles.sql`)
reading `geocoder.*`. Martin discovers function sources at startup, so a
new function needs a tileserver redeploy. Style changes also need an image
rebuild (the style is baked in). Demo copy of the comparison page lives in
the `fundermaps-development` Space under `maplibre-demo/`.
