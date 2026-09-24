# Foundation-type model 2026.2 (M6c): production scoring

`train_predict.py` trains the winning model from the 2026-09-24 study (`../scripts/30_models.py`, method
**M6c**) once, on all labelled panden, and scores every pand in `data.building_precomputed`.

## How to run

```bash
cd ~/ft-research
.venv/bin/python prod/train_predict.py --label-date 2026-09-24   # default: today
# --rebuild   recompute prod/work/base.parquet (otherwise reused if present)
```

Takes about 11 min and peaks at about 4.6 GB RSS on this VM (4 vCPU / 7 GB), measured on the last run. The DuckDB stage runs in a
child process so its memory is freed before the numpy/LightGBM stage. It does not connect to Postgres.

Outputs (in `prod/out/`):

| file | what |
|---|---|
| `model_foundation_2026_2.csv.gz` | `building_id,p_wood,p_no_pile,p_concrete,family,confidence,evidence`, one row per pand |
| `model_foundation_2026_2.lgb` | LightGBM model (text format, best iteration only) |
| `model_foundation_2026_2.meta.json` | feature order, soil code map, params, best iteration, kNN and evidence constants |
| `run.log` | stdout of the last run, including the distributions and sanity check |

`prod/work/` holds intermediate files (`base.parquet`, `pred.parquet`, `soil_codes.csv`). You can delete it.

## Inputs and how to re-extract them

All three are read-only dumps made with `../psql.sh`, which opens read-only transactions against the private host:

```bash
cd ~/ft-research
./psql.sh -f sql/01_samples.sql                                   # writes data/samples.csv
./psql.sh -f sql/02_buildings.sql | gzip > data/buildings.csv.gz  # all panden + model inputs + RD centroid
./psql.sh -f sql/04_clusters.sql  | gzip > data/clusters.csv.gz   # data.building_cluster + supercluster
```

(`03_gm1900_city.sql` is only needed for the study's Sneek subset, not here.)

The script builds the **labels** itself from `samples.csv`, using the same rules as `scripts/10_labels.py`:
- It drops deleted samples and inquiries, and all `quickscan` samples (those are circular).
- `document_date` must be on or before `--label-date` and on or after BAG built year minus 5 years.
- It keeps one leading sample per pand, ordered by inquiry-type rank, then newest `document_date`, then `sample_id`.
- It maps the leading sample to a family: wood, no_pile or concrete. Panden whose leading sample is
  `combined`/`other` are left unlabelled.

At label date 2026-09-24 this gives 213,676 labelled panden, of which 212,385 exist in `buildings.csv.gz`.
That matches the study.

## Features (36, identical to the study's `LGB_FULL`)

- **Attributes:** cy, height, address_count, ground_level, surface_area, soil (categorical), gw_level,
  pleistocene_depth, subsidence_velocity.
- **Label-free context:** `ctx_*` from a 200 m grid over a 3x3 window (density, mean cy, share before 1930 and
  before 1965, mean height), and `buurt_*` aggregates (n, median cy, share before 1930, mean ground level, mean height).
- **Location:** RD x, y.
- **Label-derived:**
  - `knn_*`: the K=30 nearest labelled panden, weighted by exp(-d/200 m)·exp(-|Δcy|/15 y). The features are
    W, the nearest distance d1, the median distance d10, and the weighted shares.
  - `near10_*`: the unweighted shares of the 10 nearest.
  - `be_*`: label count and wood/no_pile share in the same buurt × era bin.
  - `cl_*`: the same for the production cluster (`data.building_cluster`).

**Leakage control:** the same as in the study. For the **training rows**, every label-derived feature is computed
report-grouped leave-one-out: the row's own label and every label from the same inquiry are removed. This
includes the kNN, where up to K+60 neighbours are fetched so that K valid ones remain. **Scoring** uses label
features built from **all** labels, so a labelled pand sees its own label in the kNN (d=0) and in buurt × era.
That is intended: it is the best estimate given everything we know. The raw label should still take priority
over the model wherever we show a known type.

Training uses the study's LightGBM params unchanged. Early stopping (patience 50, max 2000 rounds) runs on a
10% validation split grouped by inquiry, using the study's hash `md5('v'+inquiry_id) % 10 == 0`. The saved model
contains the best iteration only.

## Output columns

- `p_wood, p_no_pile, p_concrete`: class probabilities rounded to 3 decimals by the largest-remainder method,
  so every row **sums to exactly 1.000**.
- `family` = argmax of the unrounded probabilities. `confidence` = the rounded probability of that family.
- `evidence`: how much ground truth is near this pand. The rule is applied in this order:
  1. `local`: at least 1 label in the same buurt × era bin (`be_n >= 1`), **or** the nearest label is within
     250 m (`knn_d1 <= 250`). All labels are counted, so labelled panden are always `local`.
  2. `municipal`: not local, but the pand's municipality has **30 or more labels**.
  3. `none`: everything else. This includes the ~3k panden without a buurt or municipality.

  Treat `none`, and most of `municipal`, as a prior from attributes and context, not as local knowledge. The study
  found that wood gets under-predicted as the evidence gets weaker.

## Last run (2026-09-24, label date 2026-09-24)

- Wall time 10:58, peak RSS 4.55 GB. 11,321,489 rows written.
- Training: 174,659 rows, with 37,726 held out for validation (grouped by inquiry). Best iteration 164,
  validation multi_logloss 0.315.
- Family: no_pile 59.8%, concrete 31.4%, wood 8.7%.
- Evidence: none 66.9%, local 17.0%, municipal 16.0%.
- Wood share by evidence tier: local 21.5%, municipal 10.8%, none 5.0%.
- In-sample sanity on labelled panden (**not** an accuracy estimate):
  - 0.971 as scored (own label visible).
  - 0.965 with the LOO training features.
- Out-of-sample accuracy is in `../results.csv` (M6c):
  - 0.858 on a random 20% of reports.
  - 0.768 on held-out municipalities.
  - 0.39 in Súdwest-Fryslân and 0.11 in Sneek, where local labels are scarce.
- Every feature was checked against the study's `label_feats()` and `feat.parquet`. They matched with zero mismatches.
