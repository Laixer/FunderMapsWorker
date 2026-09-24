# model-2026.2 candidate — probabilistic foundation type (Worker #152)

A LightGBM model ("M6c") that gives every pand a probability for each foundation
family (wood / no_pile / concrete), **beside** the frozen model-2024.1. It is not
served to customers. It is visible only in the mapset `model-2026-2-candidate`,
linked to FunderMaps B.V.

Why this model: read-only study of 2026-09-24 (explainer chapter 4,
https://fundermaps-development.ams3.digitaloceanspaces.com/artifacts/model-uitleg-2026-09-23.html).
Tested per report and per municipality: 86% vs 57% family accuracy (random 20% of
reports), 77% vs 39% (held-out municipalities), 84% vs 51% (Utrecht). It fails, as
every method does, in municipalities without local reports (Sneek). Hence the
`evidence` column.

## Files
| file | what |
|---|---|
| `train_predict.py` | the whole pipeline: labels → features → train → score all panden → CSV |
| `README-scoring.md` | details: features, leakage rule (report-grouped LOO), evidence tiers, last-run numbers |
| `sql/01–04*.sql` | the read-only extracts it needs (run with `default_transaction_read_only=on`) |
| `model_foundation_2026_2.meta.json` | feature order, params and best iteration of the last run |
| `requirements.txt` | Python deps (not Bun: this step is Python/LightGBM) |
| `mapset.sql` | the FunderMaps B.V.-only mapset, run after the table is loaded |
| `../../db/migrations/20260924_001_candidate_2026_2_foundation.sql` | table `data.model_foundation_2026_2` + Martin function `maplayer.foundation_candidate` |

## Apply (Yorick)
1. `bun run migrate` (prod: `~/bin/fm-migrate-prod.sh`) applies `20260924_001`.
2. Load the scores. The last run is on agent0 at
   `~/ft-research/prod/out/model_foundation_2026_2.csv.gz`, 11,321,489 rows:
   ```sql
   \copy data.model_foundation_2026_2 (building_id, p_wood, p_no_pile, p_concrete, family, confidence, evidence)
     FROM PROGRAM 'gzip -dc ~/ft-research/prod/out/model_foundation_2026_2.csv.gz' WITH (FORMAT csv, HEADER true)
   ANALYZE data.model_foundation_2026_2;
   ```
3. Run `psql -f model/2026-2/mapset.sql`.
4. Merge WebFront #309 (the layer style).
5. Check: `https://tiles.fundermaps.com/foundation_candidate` returns TileJSON, and the layer appears in maps for a FunderMaps B.V. user.

Re-score: `python train_predict.py [--label-date YYYY-MM-DD] [--rebuild]` (about 11 min, 4.6 GB peak on agent0), then `TRUNCATE` and reload (step 2).

## Last run (2026-09-24)
- Families: no_pile 59.8% · concrete 31.4% · wood 8.7%.
- Evidence: none 66.9% · local 17.0% · municipal 16.0%.
- Wood share by evidence tier: local 21.5%, municipal 10.8%, none 5.0%.

## Read with care
- **Two-thirds of panden have no nearby report** (`evidence = none`). For them the model falls back on building attributes and context, and under-predicts wood. That's the known wood under-prediction as evidence thins out. Always show `evidence` next to the prediction.
- **Labelled panden score close to their own label.** Scoring uses all labels. Where a pand has its own report, show the report, not the model.
- **Data leads, logic is the fallback** (Don, 2026-09-24): era/soil/height rules only matter where there is no local evidence.
