#!/usr/bin/env python3
"""Generate fundermaps-basemap.json — the MapLibre basemap style.

Recreates the look of the legacy Mapbox Studio style ``fundermaps_basemap``
(laixer/clcz2iorf003414p22imzzhnk, a warm tan monochrome) on top of
OpenFreeMap's Positron layer skeleton (OpenMapTiles schema, BSD-licensed).

The approach is a palette transplant: fetch Positron, keep its layer ids,
filters, zoom ramps and label machinery, and re-paint with the TAN palette
extracted from the legacy style. Regenerate with:

    python3 build_style.py            # writes fundermaps-basemap.json

Tiles come from OpenFreeMap (self-hostable escape hatch: Planetiler NL
extract -> PMTiles on Spaces). Glyphs (Noto Sans, openmaptiles/fonts v2.0)
and sprites (mirrored from OFM) are self-hosted on the fundermaps-tileset
Space. Admin boundaries (the purple lines) come from the Martin function
source maplayer.boundaries (sql/model/create_boundary_tiles.sql).

Not part of the worker runtime — the style is served as a static file
(currently from the fundermaps-development Space; final home TBD).
"""
import json
import urllib.request

POSITRON_URL = "https://tiles.openfreemap.org/styles/positron"
TILESERVER = "https://tiles.fundermaps.com"

# Palette extracted from mapbox://styles/laixer/clcz2iorf003414p22imzzhnk
TAN = {
    "land":          "hsl(40, 48%, 92%)",
    "land_struct":   "hsl(40, 46%, 86%)",   # piers, structures, road casings
    "residential":   "hsl(40, 47%, 90%)",
    "building":      "hsl(40, 43%, 81%)",
    "building_line": "hsl(40, 42%, 77%)",
    "road":          "hsl(40, 47%, 96%)",
    "road_subtle":   "hsl(38, 55%, 93%)",   # tunnels / low-zoom motorway
    "rail":          "hsl(40, 42%, 77%)",
    "rail_dash":     "hsl(40, 47%, 96%)",
    "water":         "hsl(205, 76%, 70%)",
    "park":          "hsl(78, 49%, 71%)",
    "wood":          "hsla(83, 45%, 70%, 0.8)",
    "aeroway":       "hsl(225, 13%, 83%)",
    "boundary":      "hsl(40, 42%, 60%)",
    "boundary_bg":   "hsl(40, 42%, 77%)",
    "label":         "hsl(0, 0%, 0%)",
    "label_muted":   "hsl(0, 0%, 27%)",
    "label_road":    "hsl(40, 47%, 41%)",
    "label_water":   "hsl(205, 60%, 35%)",
    "halo":          "hsl(40, 53%, 100%)",
    "halo_soft":     "hsla(40, 53%, 100%, 0.75)",
}

# layer-id (exact, from Positron) -> paint overrides
PAINT = {
    "background":               {"background-color": TAN["land"]},
    "park":                     {"fill-color": TAN["park"], "fill-opacity": 0.35},
    "water":                    {"fill-color": TAN["water"]},
    "waterway":                 {"line-color": TAN["water"]},
    "landcover_ice_shelf":      {"fill-color": TAN["land"]},
    "landcover_glacier":        {"fill-color": TAN["land"]},
    "landuse_residential":      {"fill-color": TAN["residential"]},
    "landcover_wood":           {"fill-color": TAN["wood"]},
    "building":                 {"fill-color": TAN["building"], "fill-outline-color": TAN["building_line"]},
    "tunnel_motorway_casing":   {"line-color": TAN["land_struct"]},
    "tunnel_motorway_inner":    {"line-color": TAN["road_subtle"]},
    "aeroway-taxiway":          {"line-color": TAN["aeroway"]},
    "aeroway-runway-casing":    {"line-color": TAN["aeroway"]},
    "aeroway-area":             {"fill-color": TAN["aeroway"]},
    "aeroway-runway":           {"line-color": TAN["aeroway"]},
    "road_area_pier":           {"fill-color": TAN["land_struct"]},
    "road_pier":                {"line-color": TAN["land_struct"]},
    "highway_path":             {"line-color": TAN["road"]},
    "highway_minor":            {"line-color": TAN["road"]},
    "highway_major_casing":     {"line-color": TAN["land_struct"]},
    "highway_major_inner":      {"line-color": TAN["road"]},
    "highway_major_subtle":     {"line-color": TAN["road_subtle"]},
    "highway_motorway_casing":  {"line-color": TAN["land_struct"]},
    "highway_motorway_inner":   {"line-color": ["interpolate", ["linear"], ["zoom"],
                                 5.8, TAN["road_subtle"], 6, TAN["road"]]},
    "highway_motorway_subtle":  {"line-color": TAN["road_subtle"]},
    "railway_transit":          {"line-color": TAN["rail"]},
    "railway_transit_dashline": {"line-color": TAN["rail_dash"]},
    "railway_service":          {"line-color": TAN["rail"]},
    "railway_service_dashline": {"line-color": TAN["rail_dash"]},
    "railway":                  {"line-color": TAN["rail"]},
    "railway_dashline":         {"line-color": TAN["rail_dash"]},
    "highway_motorway_bridge_casing": {"line-color": TAN["land_struct"]},
    "highway_motorway_bridge_inner":  {"line-color": ["interpolate", ["linear"], ["zoom"],
                                       5.8, TAN["road_subtle"], 6, TAN["road"]]},
    "boundary_3":               {"line-color": TAN["boundary_bg"]},
    "boundary_2":               {"line-color": TAN["boundary"]},
    "boundary_disputed":        {"line-color": TAN["boundary"]},
    "waterway_line_label":      {"text-color": TAN["label_water"], "text-halo-color": TAN["halo_soft"]},
    "water_name_point_label":   {"text-color": TAN["label_water"], "text-halo-color": TAN["halo_soft"]},
    "water_name_line_label":    {"text-color": TAN["label_water"], "text-halo-color": TAN["halo_soft"]},
    "highway-name-path":        {"text-color": TAN["label_road"], "text-halo-color": TAN["halo"]},
    "highway-name-minor":       {"text-color": TAN["label_road"], "text-halo-color": TAN["halo"]},
    "highway-name-major":       {"text-color": TAN["label_road"], "text-halo-color": TAN["halo"]},
    "airport":                  {"text-color": TAN["label_muted"], "text-halo-color": TAN["halo"]},
    "label_other":              {"text-color": TAN["label_muted"], "text-halo-color": TAN["halo_soft"]},
    "label_village":            {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_town":               {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_state":              {"text-color": TAN["label_muted"], "text-halo-color": TAN["halo"]},
    "label_city":               {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_city_capital":       {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_country_3":          {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_country_2":          {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
    "label_country_1":          {"text-color": TAN["label"], "text-halo-color": TAN["halo"]},
}

# FunderMaps admin boundaries — the purple lines from the legacy style,
# served by the Martin function source maplayer.boundaries. Inserted below
# the label layers' start so lines never overprint text.
BOUNDARY_LAYERS = [
    {
        "id": "fundermaps-municipality",
        "type": "line",
        "source": "fundermaps_boundaries",
        "source-layer": "municipality",
        "minzoom": 7,
        "paint": {"line-color": "hsl(267, 75%, 31%)", "line-width": 1.5},
    },
    {
        "id": "fundermaps-district",
        "type": "line",
        "source": "fundermaps_boundaries",
        "source-layer": "district",
        "minzoom": 10,
        "paint": {"line-color": "hsl(282, 68%, 38%)", "line-width": 1},
    },
    {
        "id": "fundermaps-neighborhood",
        "type": "line",
        "source": "fundermaps_boundaries",
        "source-layer": "neighborhood",
        "minzoom": 10,
        "paint": {"line-color": "hsl(291, 47%, 60%)", "line-width": 1},
    },
]


def main() -> None:
    # OpenFreeMap rejects urllib's default User-Agent with a 403.
    req = urllib.request.Request(POSITRON_URL, headers={"User-Agent": "fundermaps-style-build"})
    with urllib.request.urlopen(req) as resp:
        style = json.load(resp)

    style["name"] = "FunderMaps basemap"
    style.pop("id", None)

    # Glyphs and sprites come from Martin (TTFs and SVGs baked into the
    # tileserver image). Chrome's Local Network Access blocks browser
    # fetches to *.digitaloceanspaces.com from public origins, so
    # browser-fetched assets must live behind tiles.fundermaps.com.
    style["glyphs"] = f"{TILESERVER}/font/{{fontstack}}/{{range}}"
    style["sprite"] = f"{TILESERVER}/sprite/basemap"

    # Admin boundaries from our own tileserver, drawn under the labels.
    style["sources"]["fundermaps_boundaries"] = {
        "type": "vector",
        "url": f"{TILESERVER}/boundaries",
    }
    first_symbol = next(i for i, l in enumerate(style["layers"])
                        if l["type"] == "symbol")
    style["layers"][first_symbol:first_symbol] = BOUNDARY_LAYERS

    layer_ids = {layer["id"] for layer in style["layers"]}
    missed = [lid for lid in PAINT if lid not in layer_ids]
    if missed:
        # Positron upstream renamed/removed layers; the palette map needs a review.
        raise SystemExit(f"overrides without a target layer: {missed}")

    patched = 0
    for layer in style["layers"]:
        override = PAINT.get(layer["id"])
        if override:
            layer.setdefault("paint", {}).update(override)
            patched += 1

    with open("fundermaps-basemap.json", "w") as fh:
        json.dump(style, fh, indent=1)
    print(f"patched {patched}/{len(style['layers'])} layers -> fundermaps-basemap.json")


if __name__ == "__main__":
    main()
