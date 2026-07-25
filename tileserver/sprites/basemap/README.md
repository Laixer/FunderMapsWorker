# Basemap sprite SVGs

Source icons for the `basemap` sprite Martin generates and serves at
`/sprite/basemap`. Only the icons the basemap style actually references:

- `road_1..road_6.svg` — generic highway shields (one per ref length);
  `default_*.svg` from [maputnik/osm-liberty] (BSD-licensed style repo,
  icons CC0/BSD), renamed to the icon names the style inherited from the
  OpenFreeMap sprite.
- `airport_11.svg` — osm-liberty iconset (Maki-derived, CC0).
- `circle_11_black.svg` — hand-made place dot for village/town/city
  labels at low zoom.

US shield layers (`us-interstate_*` etc.) reference icons we deliberately
do not ship — those networks never occur in NL data, so the icons are
never requested.

[maputnik/osm-liberty]: https://github.com/maputnik/osm-liberty
