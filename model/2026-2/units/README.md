# Bouwkundige eenheden (Don, 2026-09-28)

A unit = panden built together on one foundation: they can never have different foundation types.
Rule (variant 1, Don): a seam = two BAG contours running >= 2.0 m within 0.25 m of each other. A seam is cut
("apart") when (1) the BAG building year differs, (2) the height differs by > 0.5 m, (3) smallest/largest
footprint < 0.75, or (4) both panden have an established foundation type and they differ; a missing value drops
only that test. Units = connected components over the uncut seams, never across a current FunderMaps cluster
border; seams are joined strongest (longest) first and a join that would bring two different established types
into one unit is skipped (the chain case).

Run (read-only extracts, ~20 min for 355 municipalities at 2 in parallel; units ~80 min on agent0):
    UNITS_WORK=~/work/units ./extract_gm.sh
    UNITS_WORK=~/work/units python units_nl.py
then copy `units.csv.gz` to `../../data/units.csv.gz`; `pool_clusters.py` picks it up instead of the clusters.

Last run 2026-09-28: 11,390,458 panden, 5,722,692 seams (3,626,790 together / 2,095,902 apart; by reason 1:
856,592 · 2: 1,207,508 · 3: 1,426,885 · 4: 7,119), 7,819,374 units, 41 chain joins skipped, 0 units with two
established types. Schiedam check against Don's own run: see the model explainer.
Leave-one-report-out: passing the other reports' majority to a pand is right 99.8% within a unit (7,034 panden)
vs 91.8% within a current cluster (24,810 panden).
