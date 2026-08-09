# Running several risk models side by side

**Status:** design, not built.
**Written:** 2026-08-09.
**Decisions taken:** the current model's logic is frozen and will not change
again; we need room for many candidate models; customers will be able to pin a
version. No per-run history is kept.

---

## 1. Why

The model in production is final. Everything new — Model 4 with GeoTOP and
InSAR, Don's QuickScan override rule, the wood under-prediction fix — has to
land as a *different* model running beside it, not as edits to the one banks
already make decisions on.

That turns a single pipeline into a small platform: several models producing
output at once, a way to tell them apart, a way to score a newcomer before it
goes anywhere near a customer, and a way for a customer to say "keep giving me
the one I integrated against".

## 2. Name them properly, and not "v3 / v4"

We already use v3 and v4 for **API versions** — `/api/v3` on the C# Webservice,
`/v4/product/*` on the TS one. Informally we also call the current model V3 and
the next one Model 4. Those are different axes that will collide in every
support conversation and every customer email.

**Models get their own namespace and never reuse an API version number.** A
release-style slug reads unambiguously in a response body and sorts naturally:

```
model-2024.1     the frozen current model
model-2026.1     Model 4 (GeoTOP + InSAR)
model-2026.2-rc1 a candidate
```

Nobody ever has to ask whether "v4" means the API or the model again.

## 3. A version records the data it ran on

The same SQL over a newer BAG import produces different output, so a version
that says nothing about its inputs makes every later comparison ambiguous: *did
the model change, or did the ground under it?* `inputs` is what answers that.

**No hashes or checksums** — deliberately, by decision on 2026-08-09. A version
is identified by its slug, described by its notes, and tied to its data by
`inputs`. The logic itself is pinned by the fact that a model's SQL is not
edited after it is registered: new logic means a new slug.

```sql
CREATE TABLE data.model_version (
    id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug          text NOT NULL UNIQUE,          -- 'model-2026.1'
    title         text NOT NULL,
    status        data.model_status NOT NULL,    -- see §4
    -- vintage and row-count fingerprint of every input, so a comparison
    -- between versions can attribute itself to logic or to data
    inputs        jsonb NOT NULL,                -- {bag_building: {rows: …},
                                                 --  building_subsidence: {rows: …,
                                                 --    vintage: '2024-11-19'}, …}
    is_default    boolean NOT NULL DEFAULT false,
    notes         text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    activated_at  timestamptz,
    frozen_at     timestamptz,
    retire_after  date                           -- the support promise, §8
);
```

`inputs` is `jsonb` deliberately: Model 4 adds sources we have not named yet, and
a rigid column per input would need a migration each time. Row counts are stored
alongside dates because most input tables carry no date column at all, and a
count detects change better than a hand-typed date nobody updates.

## 4. Lifecycle

```
draft ──► candidate ──► active ──► frozen ──► deprecated ──► retired
                │                     │
                └── rejected          └── (pinned customers still served)
```

- **draft** — SQL exists, nothing materialised.
- **candidate** — runs on the evaluation sample only (§6). Scored, not served.
- **active** — fully materialised nightly, served as the default.
- **frozen** — logic will not change again; still refreshed against live data.
  *This is where the current model sits.*
- **deprecated** — still served to customers pinned to it, no new pins accepted,
  `retire_after` set and communicated.
- **retired** — partition dropped.

Only `active`, `frozen` and `deprecated` cost a nightly full run.

## 5. Storage: one matview per version, and a pointer view

The instinct is to partition a table by version. **Don't.** A materialized view
cannot be partitioned, so that route means replacing the existing refresh
machinery with a hand-rolled staging-and-swap — and giving up
`CONCURRENTLY`, which is what currently lets 11.2M rows rebuild for 46 minutes
without blocking a single customer read.

What is actually there today is one line:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY data.model_risk_static;
```

So keep it, and give each fully-materialised version its own matview:

```sql
-- the frozen current model, renamed in place; dependents follow automatically
-- because Postgres tracks them by OID, not by name
ALTER MATERIALIZED VIEW data.model_risk_static RENAME TO model_risk_static_2024_1;

-- every consumer that says model_risk_static keeps working, unchanged
CREATE VIEW data.model_risk_static AS
SELECT * FROM data.model_risk_static_2024_1;
```

Adding a model is then one more matview and **one more line in the refresh
script**. Switching the default is a `CREATE OR REPLACE VIEW`. Retiring a model
is a `DROP`. No new machinery, and the rollback for each step is the inverse of
the step.

Partitioning would win if we had many full versions and wanted partition
pruning. We will not: §6 keeps candidates off the national dataset, so the
number of full materialisations stays at two or three.

The three objects that depend on the model directly —
`data.building_geo_hierarchy`, `data.statistics_product_foundation_risk`,
`data.statistics_product_foundation_type` — will follow the rename to the
concrete matview. Recreate them against the pointer view instead, so they track
the default rather than pinning themselves to the frozen model by accident.

The rest of the coupling is runtime (the API, the Webservice, Martin's tile SQL,
the GPKG export) and has to be found by reading those services, not by asking
Postgres.

**Cost per fully-materialised version: ~3.8 GB**, against a 70 GB database on a
16 GB-RAM plan where RAM is already the binding constraint, not CPU. Two or
three full versions are comfortable. Ten are not — which §6 exists to prevent.

The 18 `data.statistics_*` matviews (77 MB total) and the tile layers are
**produced for the default version only** unless someone asks otherwise. A
national statistic or a map colour has no meaning without saying which model it
came from, and duplicating both per version buys little.

## 6. Candidates must not run nationally

The nightly flow takes **~46 minutes** and runs twice a day, on a Windmill
instance that has **exactly one worker** — all flow parallelism serializes
instance-wide. Two full models is ~90 minutes a run; three is over two hours,
twice daily, on the same worker that also has to do BAG imports and exports.

So the framework's central rule: **a candidate is scored on a sample, never on
all 11.2M buildings.**

```
evaluation sample = the 311,145 buildings with a surveyed foundation type
                  + a stratified national sample across era × soil × region
```

That is ~3% of the data — roughly 100 MB and a couple of minutes instead of
3.8 GB and 46. It is also the *only* part of the country where a candidate can
be judged at all, since the rest has nothing to check against. A candidate gets
promoted to a full national run when it has earned it, not to find out whether
it has.

## 7. The promotion gate already exists

`sql/validate/` is the scoring harness, and a candidate must beat the incumbent
on it before promotion:

- **wood recall against false-alarm rate** — not accuracy. Moving the soft-soil
  height cutoff to where the data puts it raises accuracy 0.2 points while
  losing 7.8 points of wood detection; a gate scored on accuracy would wave that
  through (`rejected_threshold_change.sql`).
- **calibration** — if the model emits probabilities, predicted 30% must mean
  ~30% observed.
- **population sanity** — national wood share, so a candidate that quietly
  reclassifies two million buildings cannot arrive unannounced.
- **movement vs the incumbent** — how many buildings change, and in which
  direction.

Recording the score against the version id makes promotion an argument about
numbers rather than about who wrote it.

## 8. Customer pinning is a support promise, not a query parameter

Pinning is the decision with the longest tail. Every pinned version must stay
materialised and refreshed for as long as the promise lasts, so before it ships
we need answers to:

- **How many versions do we keep alive at once?** Each is ~3.8 GB and a share of
  a 46-minute nightly window that already runs on one worker.
- **How long is a deprecation notice?** `retire_after` is the field; the number
  is a commercial decision.
- **What does a customer get if they pin nothing?** Default must mean *current
  active*, and it must be stated in the contract, not inferred.

Mechanically: the Webservice takes an optional model slug, the response states
which model answered, and `application.product_tracker` records the version per
request — which is also the honest basis for any future per-model pricing.

**One thing pinning does not give them, and we must say so plainly.** Because we
keep no history, a pinned version's *logic* is fixed but its *answers* still move
as new inquiries land. A bank pinned to `model-2024.1` gets a different result in
March than in January. That is usually what they want. It is not what "pinned"
sounds like.

## 9. The history gap, and a cheap way to close the worst of it

The decision is to keep no per-run history, which rules out the
diff-between-runs product and means we cannot reconstruct what the model said on
any past date. Storing full snapshots would cost ~3.8 GB per run per model, so
this is a reasonable trade.

But one question survives that trade and will eventually be asked in writing:
**"what did you tell us in March?"** — during a dispute, an audit, or a claim.

That question can be answered without any model history at all, by recording
what we actually *served*:

> On each billable request, `product_tracker` already logs the call. Extend it
> with the model version and the handful of values returned. Volume is bounded by
> request traffic rather than by 11.2M buildings, it compresses well as a
> TimescaleDB hypertable alongside the existing product data, and it answers the
> dispute question exactly — not what the model would have said, but what we
> told that customer on that day.

Worth doing at the same time as §8, since both touch the same code path.

## 10. Order of work

| Step | Work | Size | Why here |
|---|---|---|---|
| 1 | Registry table + lifecycle enum; register the current model as `frozen` with its input vintages | one migration, ~60 lines | Pure addition, nothing reads it yet. Starts the provenance record immediately. |
| 2 | Rename the matview, add the pointer view, repoint the three dependents | one migration + 3 `CREATE OR REPLACE` | The migration everything else needs. No consumer changes. Reversible by renaming back. |
| 3 | Evaluation sample + wire `sql/validate/` to score a named version | one view + arguments on existing scripts | Makes Model 4 development safe before Model 4 exists. |
| 4 | Second matview + one line in `refresh_risk_model` | one line, once a model exists | Only now does the nightly window grow. Do not do this before there is a model to put in it. |
| 5 | Version in the Webservice response; `product_tracker` records it | small | Reversible, no contract change yet. |
| 6 | Customer pinning + support policy | the real work is the policy | Last, because it is a promise rather than a feature. |

Steps 1–3 are roughly two days and touch no customer. Steps 4–6 should not be
built speculatively: step 4 waits for a second model to exist, and steps 5–6 wait
for a commercial decision. A framework built before it has a second occupant is
a framework built against guesses.

Steps 1–3 need no decision from anyone and do not touch a customer. Step 6 needs
Don, and should not land while the NWWI v4 cutover and the C# Webservice EOL
(August 2026) are still in flight — adding a second version axis mid-migration
is how support tickets become archaeology.

## 11. Open questions

1. **Which model do the map and the GPKG export show?** Default only is assumed
   above. If the WebFront should let a user switch models, the tile layer needs a
   version attribute and Martin needs a source per version.
2. **Do the statistics matviews follow the default, or does a pinned customer
   see statistics from their own model?** Assumed default-only.
3. **What happens to a pinned customer when their model is retired** — forced
   migration, or a final snapshot handed over?
4. **Does Model 4 replace or coexist long-term?** Coexistence is assumed, which
   is what makes the support policy in §8 load-bearing.
