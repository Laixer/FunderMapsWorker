# `sql/validate/` — does the model tell the truth?

These scripts answer a question `sql/model/` cannot: not *what* the model
computes, but whether it is **right**. They are read-only — `SELECT` plus temp
tables — and safe to run against production.

Run them with `psql`, not the worker:

```sh
psql "$DB_URL" -f sql/validate/foundation_type_accuracy.sql -v truth_status=done
```

---

## Why these exist

Before 2026-08-09 nothing in this repository measured model accuracy. The one
thing that looked like it did — `f/fundermaps/data/validate_model_drift` in
Windmill, against `validation/risk_model_reference.csv` — compares the model to
an **exported snapshot of its own past output**. 167 of that file's 783 rows
carry `foundation_type_reliability = indicative`, meaning no inquiry backs them
and nobody ever surveyed the building. It measures stability over time. It
cannot measure accuracy, and no number from it may be quoted as such
(issue #78).

These scripts use the only real ground truth we hold: `report.inquiry_sample`
rows, where a surveyor physically looked and wrote down what they found.

## The standing caveat, which applies to every number below

**The truth set is buildings someone chose to inspect, and people inspect
buildings they are already worried about.** Nothing here is population accuracy,
and no data we currently hold can make it so. Say this out loud whenever a
figure from these scripts is quoted. `wood_underprediction.sql` is the partial
answer — it defuses the objection for one specific claim by measuring inside
neighbourhoods that are already heavily inspected — but it does not remove it.

## Two traps, both of which cost real time

**Leakage.** Production calls the classifier as

```sql
data.indicative_foundation_type(
    COALESCE(established.built_year, bp.construction_year_bag), ...)
```

so it reads the construction year off the very inquiry it is being scored
against. Every script here passes `bp.construction_year_bag` alone. Pass the
`COALESCE` and the model marks its own homework.

**Family folding.** The classifier can only ever emit four values
(`no_pile` / `concrete` / `wood_charger` / `wood`) while surveyors record 13 or
more. Scoring exact equality punishes it for answering `wood` when the surveyor
wrote `wood_rotterdam`. Score the family — `data.is_wood_family()` /
`data.is_no_pile_family()` — as every script here does.

Two smaller ones: 12,645 buildings carry inspections asserting **different**
foundation types for the same building, and are excluded from the denominator
rather than resolved; and 101 samples are soft-deleted (`delete_date`), which
moves only 22 buildings and is therefore immaterial but worth filtering.

---

## The frozen benchmark

`data.model_evaluation_sample` (created 2026-08-09) is what a **candidate**
model is scored against. Two kinds of row:

| purpose | rows | what it is |
|---|---|---|
| `truth` | 296,839 | buildings a surveyor inspected, answer frozen at creation, split 207,888 train / 88,951 test (39.4% wood) |
| `population` | 103,687 | stratified national sample, no truth — answers "what does this model say about the country", not "is it right" |

**It is a table, not a view, and that is the point.** The truth set grows daily
as inquiries land; a view would mean a candidate scored on Tuesday and one
scored on Friday were measured against different benchmarks, and the gap between
them would be partly the data. Sampling is deterministic on `hashtext(building_id)`,
so the split never moves. Regenerate deliberately and bump `sample_version`.

**Weight population figures, never average them raw.** The sample is
proportional except for a floor of 2,000 rows per stratum, which keeps the two
tiny unknown-soil strata alive and makes the raw sample unrepresentative.
Measured on the current model: national wood share reads **5.97% raw** against
**3.74% weighted**, where the true figure is 3.71%. Raw overstates by 60%. Join
`data.model_evaluation_stratum_weight` and weight by `national_buildings`.

## The scripts

| Script | Answers |
|---|---|
| `foundation_type_accuracy.sql` | How often is the classifier right, and how much wood does it miss? |
| `wood_underprediction.sql` | Is the shortfall real, or just an artefact of who gets inspected? |
| `foundation_type_frontier.sql` | Would a calibrated probability beat the decision tree, and at what operating point? |
| `rejected_threshold_change.sql` | A change that looked correct, measured worse, and must not be re-attempted blindly. |

## Results as of 2026-08-09

Held-out half, 88,946 buildings, fitted on the other 70%.

| | wood found | false alarms | accuracy |
|---|---|---|---|
| Classifier as deployed | 60.2% | 11.2% | 67.3% |
| Calibrated probability @ 0.50 | **72.1%** | 11.1% | **82.2%** |
| Calibrated probability @ 0.35 | 83.2% | 21.9% | 80.2% |

The probability model beats the deployed tree on every axis simultaneously at
the same false-alarm rate, and its probabilities are well calibrated (predicted
20–30% → 25.3% observed; 90–100% → 98.0%).

Wood share by tier — the fingerprint of the whole problem:

| Tier | Buildings | % wood |
|---|---|---|
| `established` | 305,128 | 39.8% |
| `cluster` | 146,102 | 14.2% |
| `supercluster` | 1,329,898 | 7.4% |
| `indicative` | 9,460,060 | **1.86%** |

Nationally that is 416,573 buildings called wood today against 948,156 at
threshold 0.50 — and **712,466** buildings our own data puts above even odds of
wooden piles while the product reports otherwise.

## Two conclusions worth keeping

**Accuracy is the wrong objective for this model.** Moving the soft-soil height
cutoff from 8.5 m to 10 m — where the data genuinely puts the cliff — raises
accuracy 0.2 points and drops wood detection from 60.2% to 52.4%. A missed
wooden pile and a wasted inspection are not the same cost and must not be
scored as if they were. See `rejected_threshold_change.sql`.

**National features have a ceiling.** Fitted while excluding the
heavily-inspected neighbourhoods, the probability model predicts 22.3% wood for
their uninspected buildings where inspections next door found 61.8% — worse than
the deployed tree manages there. Age, height, soil and ground level cannot
encode *this is central Zaandam*. The missing ingredient is local evidence, not
more national inputs.
