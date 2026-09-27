# model-2026.2 candidate — foundation type with a reliability grade (Worker #152)

Gives every pand a foundation type (wood / wood with concrete top / shallow / concrete), the probabilities
behind it, and a reliability grade, **beside** the frozen model-2024.1. Not served to customers: visible only in
the mapset `model-2026-2-candidate`, linked to FunderMaps B.V.

**rc2 (2026-09-27), the model Don approved on 2026-09-26/27** (explainer chapters 10–11,
https://fundermaps-development.ams3.digitaloceanspaces.com/artifacts/model-uitleg-2026-09-23.html):
- **family** = a blend of two LightGBM models: **c** (attributes + context + nearby report labels) where the
  buurt has report labels, else the mean of c and **a** (attributes + context only). a is better where a
  municipality has no reports of its own, c where it does.
- **model d** splits a wood family into wood pile / wood pile with concrete top (`wood_charger`).
- **data leads** (Don: "als iets bekend is op pand geldt dat, anders het model"): a report on the pand, else one
  of the 100 reliable old QuickScans (`qs_reliable_inquiries.csv`: the 88 of 2026-09-26 minus the Perfectkeur
  import 136265, plus 13 re-scored Rotterdam reports) overrides the model; `source` says which, grade
  `vastgesteld`. Those QuickScans are never training labels (they made Utrecht worse).
- **grade** = f(evidence tier, confidence) from the out-of-sample study (`grade_lookup.csv`, lower bound of the
  per-municipality 95% CI): zeer betrouwbaar ≈96% correct, betrouwbaar ≈83%.

Tested against model-2024.1 (family, same test sets): random 20% of reports 86% vs 74%, held-out
municipalities 74% vs 39%, the 4 test areas pooled 72% vs 50%. Worse in Súdwest-Fryslân (40% vs 45%) and Sneek
(12% vs 17%); both are graded `zwak`. Model d within wood: 88% where the buurt has reports, 84% held-out
municipalities (always "wood pile" would score 53% / 19%).

## Files
| file | what |
|---|---|
| `train_predict.py` | the whole pipeline: labels → features → train c, a, d → blend, own evidence, grade → CSV |
| `qs_reliable_inquiries.csv` | the 100 reliable old QuickScans that count on their own pand |
| `grade_lookup.csv` | evidence tier × confidence band → grade (from the out-of-sample study) |
| `README-scoring.md` | details: features, leakage rule (report-grouped LOO), evidence tiers, last-run numbers |
| `sql/01–04*.sql` | the read-only extracts it needs (run with `default_transaction_read_only=on`) |
| `model_foundation_2026_2.meta.json` | feature order, params and best iteration of the last run |
| `requirements.txt` | Python deps (not Bun: this step is Python/LightGBM) |
| `mapset.sql` | the FunderMaps B.V.-only mapset, run after the table is loaded |
| `../../db/migrations/20260924_001_candidate_2026_2_foundation.sql` | table `data.model_foundation_2026_2` + Martin function `maplayer.foundation_candidate` |

## Apply (Yorick)
1. `bun run migrate` (prod: `~/bin/fm-migrate-prod.sh`) applies `20260924_001`.
2. Load the scores. The last run is on agent0 at
   `~/ft-research/worker_run/2026-2/out/model_foundation_2026_2.csv.gz`, 11,321,489 rows:
   ```sql
   \copy data.model_foundation_2026_2 (building_id, p_wood, p_no_pile, p_concrete, p_oplanger, family,
          foundation_type, confidence, evidence, grade, source)
     FROM PROGRAM 'gzip -dc ~/ft-research/worker_run/2026-2/out/model_foundation_2026_2.csv.gz' WITH (FORMAT csv, HEADER true)
   ANALYZE data.model_foundation_2026_2;
   ```
3. Run `psql -f model/2026-2/mapset.sql`.
4. Merge WebFront #309 (the layer style).
5. Check: `https://tiles.fundermaps.com/foundation_candidate` returns TileJSON, and the layer appears in maps for a FunderMaps B.V. user.

Re-score: `python train_predict.py [--label-date YYYY-MM-DD] [--rebuild]` (about 16 min, 5.4 GB peak on agent0), then `TRUNCATE` and reload (step 2).

## Last run (2026-09-27, rc2, label date 2026-09-24)
- Labels: report samples without `quickscan` (vervallen) and without `facade_scan` (QuickScan addendum, our own
  output = circular). 212,835 panden; 81,946 wood, of which 36% with concrete top (model d).
- Foundation type: no_pile 54.4% · concrete 37.4% · wood with concrete top 6.1% · wood 2.1%.
- Grade: vastgesteld 2.4% · zeer betrouwbaar 4.9% · betrouwbaar 6.7% · redelijk 11.1% · zwak 75.0%.
- Source: model 97.6% · report 1.9% · reliable old QuickScan 0.5%.
- Evidence: none 67.5% · municipal 15.8% · buurt 11.9% · nabij 4.9%.

## Read with care
- **Two-thirds of panden have no nearby report** (`evidence = none`). For them the model falls back on building attributes and context, and under-predicts wood. That's the known wood under-prediction as evidence thins out. Always show `grade` next to the prediction; `zwak` promises nothing.
- **Labelled panden score close to their own label.** Scoring uses all labels. Where a pand has its own report, show the report, not the model.
- **Data leads, logic is the fallback** (Don, 2026-09-24): era/soil/height rules only matter where there is no local evidence.
