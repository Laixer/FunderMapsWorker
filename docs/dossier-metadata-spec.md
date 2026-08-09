# Dossier metadata — structuring what the `note` field is really holding

**Status:** proposal, not built. Written 2026-07-26 after auditing every note in prod.
**Touches:** `FunderMapsWorker` (schema), `FunderMapsApi` (CRUD + filters), `FunderMapsClientApp` (UI).
**Related:** [`dataops-pipeline.md`](./dataops-pipeline.md) §3 *Intake — the front door*.

---

## 0. TL;DR

The `note` field is doing three unrelated jobs, and only one of them is actually a note.

| What it holds | Rows | Where | Remedy |
|---|---|---|---|
| **A · Supply chain** — who sourced the dossier, who passed it on, and their reference number | 5,174 | `inquiry.note` | New columns. The party chain has three links and we record one. |
| **B · QuickScan outcome** — final assessment + recommended action | 864 / 849 | `inquiry_sample.note` | New enums. One field exists but is the wrong scale; the other has no field at all. |
| **C · Data-quality caveats** — "this value is an assumption" | ~800 | `inquiry.note` | A short controlled vocabulary (*kenmerken*). |

Only **C** is the tag-shaped thing. It is also the smallest. The headline is **A**.

---

## 1. Evidence

Every note in production, 2026-07-26. Corpus: **15,325 notes**.

| Table | With a note | Total | % |
|---|---:|---:|---:|
| `report.inquiry` | 9,182 | 26,656 | 34% |
| `report.inquiry_sample` | 5,306 | 490,987 | 1% |
| `report.recovery_sample` | 837 | 18,827 | 4% |
| `report.recovery` | 6 | 14 | 43% |

Pattern frequency, split by which table holds it — the split is the finding:

| Pattern | `inquiry` | `inquiry_sample` |
|---|---:|---:|
| `doorlevering vanuit …` | **5,174** | 0 |
| FRO-QuickScan / NAFO | **4,383** | **4,382** |
| FunderScan | 794 | 901 |
| `bouwkundige eenheid` | 469 | 0 |
| `eindbeoordeling …` | 1 | **864** |
| `handelingsperspectief …` | 0 | **849** |
| sloop / nieuwbouw | 145 | 0 |
| aanname / aangenomen | 71 | 0 |
| rapport ontbreekt | 37 | 0 |
| maatvoering t.o.v. vloerpeil | 31 | 0 |

Provenance and caveats live on the **dossier**; assessment outcomes live on the
**sample**. That is not an accident, and it is what decides where each new column goes.

### These notes were written by a machine

`FRO-QuickScan NAFO doorlevering vanuit FunderConsult bron: FundonService` occurs
**4,382 times byte-identically**. That is a template emitted by an import, not
something 26,000 dossiers' worth of people typed. Two consequences:

1. **Backfill is safe and near-lossless** — the strings parse deterministically.
2. **The importer should be fixed at the same time**, or it will keep writing prose
   into a field that now has columns. Backfilling without fixing the writer just
   means doing it again next quarter.

---

## 2. Finding A — the supply chain has three links and we record one

For the 5,174 dossiers carrying `doorlevering vanuit`, the recorded contractor is:

| `attribution.contractor` | n |
|---|---:|
| VastgoedNED | 4,381 |
| FunderMaps B.V. | 792 |
| Perfectkeur | 1 |

But the note says the chain is:

```
FundonService  ──bron──▶  FunderConsult  ──doorlevering──▶  VastgoedNED  ──▶  FunderMaps
   (origin)                (intermediary)                    (contractor)
      ?                          ?                          recorded
```

**Two of the three parties are unqueryable.** You cannot answer "how much of the
archive originated at FundonService", which is a commercial question, not a
technical one.

There is also an **external reference** in the note — `FRO-QuickScan 4906`,
`FunderScan REG-…`, `FunderScan-object …` — a foreign key into the supplier's own
system. Today reconciling a supplier's list against ours means grepping free text.

### Relationship to `dataops-pipeline.md`

The Data Ops design already has `dataops.dossier.channel` for intake **mechanism**
(email / upload / bulk drop / API). Supplier chain is a **different axis**: commercial
provenance, not transport. A dossier can arrive by email *from* FunderConsult
*originating at* FundonService. Both axes are needed, and this spec covers the one
the existing 26k rows already carry.

---

## 3. Finding B — the QuickScan outcome is prose, and the field for it is empty

**`eindbeoordeling`** — 864 samples. Closed vocabulary:

| value | n |
|---|---:|
| laag | 429 |
| gemiddeld | 350 |
| hoog | 83 |
| midden | 2 |

**`handelingsperspectief`** — 849 samples. Also closed:

| value | n |
|---|---:|
| monitoring door herhaling quickscan na *n* jaar | 385 |
| geen maatregelen | 356 |
| funderingsonderzoek | 81 |
| geen structurele aanpassingen | 13 |
| funderingsherstel | 5 |
| monitoring met satellietdata | 5 |

### Two traps

**Do not fold `eindbeoordeling` into `facade_scan_risk`.** That column exists on
`inquiry_sample` and is a **five-point A–E** scale (`facade_scan_risk` enum).
`eindbeoordeling` is a **three-point laag/gemiddeld/hoog** assessment. They are
different instruments. Mapping one onto the other destroys information and invents
precision. They need separate columns.

**`facade_scan_risk` is set on 1 of the 864.** The field is not wrong, it is
*unused* — the form asks for it and nobody fills it, while the same person writes
the answer into the note. Worth understanding why before adding two more fields
beside it, or they will go the same way. My guess: the note is what the supplier's
PDF says verbatim, and re-encoding it into an A–E dropdown is work with no visible
payoff. If so, the fix is that the new fields must be **what the source document
already says**, which `eindbeoordeling` and `handelingsperspectief` are.

---

## 4. Finding C — kenmerken, the controlled vocabulary

The genuinely tag-shaped residue, all dossier-level. Proposed starter set — six
terms, each earned by the data:

| Kenmerk | Meaning | Evidence |
|---|---|---:|
| `bouwkundige-eenheid` | Dossier covers a structural unit spanning several addresses | 469 |
| `sloop-of-nieuwbouw` | Building demolished or replaced since the report | 145 |
| `funderingstype-aanname` | Foundation type is inferred, not observed | 71 |
| `brondocument-ontbreekt` | Source report could not be located | 37 |
| `maatvoering-vloerpeil` | Depths are relative to floor level, **not NAP** | 31 |
| `dubbele-invoer` | Duplicate of another dossier | 12 |

**Fixed list. No free text.** If it grows past ~8 it is turning into tags and
someone should stop it. Free-form tags across four users reliably become
`rotterdam` / `Rotterdam` / `rdam` with no owner.

### `maatvoering-vloerpeil` pays for the feature on its own

`services/sampleValidation.ts` assumes every depth is metres NAP. On the 31
dossiers measured from floor level, `grondwaterstand ligt boven maaiveld` fires as a
**false positive every single time**. The flag lets the validator stand down. That
is a bug fix, not a nicety.

---

## 5. Schema

`FunderMapsWorker` owns `schema.sql`. All of this is **additive**; nothing is
dropped or retyped. The C# monolith reads `report.inquiry` and
`report.inquiry_sample` with explicitly named columns (no `SELECT *`, verified), so
new columns are invisible to it — but new **tables** are safer still, and are used
wherever the cardinality allows.

```sql
-- A · supply chain, per dossier. Own table: invisible to C#, and the chain may
--     grow a link without retyping report.inquiry.
CREATE TABLE report.inquiry_provenance (
  inquiry_id           integer PRIMARY KEY REFERENCES report.inquiry(id) ON DELETE CASCADE,
  source_contractor_id integer REFERENCES application.contractor(id),  -- bron          (FundonService)
  relayed_by_id        integer REFERENCES application.contractor(id),  -- doorlevering  (FunderConsult)
  intake_product       text,                                           -- 'fro-quickscan' | 'funderscan'
  external_reference   text,                                           -- '4906', 'REG-…'
  create_date          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON report.inquiry_provenance (source_contractor_id);
CREATE INDEX ON report.inquiry_provenance (relayed_by_id);
CREATE INDEX ON report.inquiry_provenance (external_reference);

-- B · QuickScan outcome, per address. Columns, not a table: 1:1 with the sample
--     and read on the same hot path as facade_scan_risk.
CREATE TYPE report.assessment_level AS ENUM ('laag','gemiddeld','hoog');
CREATE TYPE report.action_perspective AS ENUM (
  'geen_maatregelen', 'monitoring', 'monitoring_satelliet',
  'funderingsonderzoek', 'funderingsherstel', 'geen_structurele_aanpassingen');

ALTER TABLE report.inquiry_sample
  ADD COLUMN final_assessment    report.assessment_level,
  ADD COLUMN action_perspective  report.action_perspective,
  ADD COLUMN action_interval_years smallint;   -- the "na n jaar" in the monitoring case

-- C · kenmerken. Join table so the vocabulary can grow without a migration per term.
CREATE TABLE report.dossier_kenmerk (
  inquiry_id  integer NOT NULL REFERENCES report.inquiry(id) ON DELETE CASCADE,
  kenmerk     text    NOT NULL,          -- slug from the registry, validated app-side
  create_date timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES application.user(id),
  PRIMARY KEY (inquiry_id, kenmerk)
);
CREATE INDEX ON report.dossier_kenmerk (kenmerk);
```

**On `kenmerk` as `text` rather than an enum:** the vocabulary is enforced in the
app registry (next to `sampleEnums.ts`), not in PG. Adding a seventh term should be
a one-line PR, not a migration + a C# enum-mapping check. The July 2026 WS outage
came from exactly that coupling — see the `application.*` enum→text incident.

---

## 6. API — `FunderMapsApi`

```
GET  /api/inquiry?kenmerk=funderingstype-aanname[,…]   # AND semantics
GET  /api/inquiry?bron=<contractorId>
GET  /api/inquiry?product=fro-quickscan
GET  /api/inquiry?ref=4906                             # exact, for reconciliation
POST /api/inquiry/:id/kenmerk      { kenmerk }
DEL  /api/inquiry/:id/kenmerk/:k
```

`provenance` and `kenmerken` join into the existing inquiry serializer.
`final_assessment` / `action_perspective` join the sample serializer.

**Filtering must be server-side.** The studio's type filter is currently
client-side because `GET /inquiry` has no type parameter, so it narrows only the
visible page and the UI has to say so. Do not repeat that here — a kenmerk filter
that silently only searches page 1 is worse than no filter.

---

## 7. UI — `FunderMapsClientApp`

Nearly free; every primitive exists.

- **Registry** — `services/kenmerken.ts`, mirroring `SAMPLE_SECTIONS`: slug, Dutch
  label, one-line description, `Tone`.
- **Dossier header** — kenmerken as `Pill`s beside the status pill.
- **Explorer** — a `kenmerk` facet in `FilterBuilder`; active ones render as
  `FilterChip`s; a `Kenmerken` column in `DataTable`.
- **Bulk action bar** — the design brief already sketched `assign, approve, export,
  tag`; this is what fills the last slot.
- **Invoer** — `final_assessment` / `action_perspective` are two more entries in
  `SAMPLE_SECTIONS`, so the form, the read-only view and the completeness counts all
  pick them up for free.
- **Validation** — `sampleValidation.ts` skips NAP cross-field checks when
  `maatvoering-vloerpeil` is set.

---

## 8. Backfill

One migration per finding, each idempotent, each re-runnable. Parse from the note,
**write to the column, and leave the note alone** — no destructive edit until the
parse has been eyeballed against a sample.

```sql
-- illustrative; real version lives in sql/migrate/
INSERT INTO report.inquiry_provenance (inquiry_id, relayed_by_id, intake_product, external_reference)
SELECT i.id,
       (SELECT id FROM application.contractor WHERE name ILIKE 'FunderConsult'),
       CASE WHEN i.note ~* 'fro-?quickscan' THEN 'fro-quickscan'
            WHEN i.note ~* 'funderscan'     THEN 'funderscan' END,
       substring(i.note FROM '(?:FRO-QuickScan|REG-)\s*([0-9]{3,})')
FROM report.inquiry i
WHERE i.delete_date IS NULL AND i.note ILIKE '%doorlevering vanuit%'
ON CONFLICT (inquiry_id) DO NOTHING;
```

Coverage to expect: **A** ~5,174 · **B** ~864 / ~849 · **C** ~800.

`FundonService` and `FunderConsult` must exist in `application.contractor` first —
check before running, create if absent.

**Only strip the note once the columns are verified**, and only the machine-written
template portion. Anything a human appended stays.

---

## 9. Order of work

1. **Fix the importer first.** Whatever writes `doorlevering vanuit …` should write
   columns. Otherwise every backfill is temporary.
2. Schema migrations (Worker) → apply → fold into `schema.sql`.
3. API: serializer joins + filters.
4. Backfill migrations, verified against a sample before any note is touched.
5. Studio UI.
6. *Optional, later:* carry `funderingstype-aanname` into the Webservice so the
   caveat reaches the banks and NWWI with the value it qualifies. **This is the
   commercial payoff and it is also the one step that changes customer-facing
   output — it wants its own decision, not a ride-along.**

## 10. Open questions — for Yorick and Don, not for me

1. **Is the six-term kenmerk list right?** A controlled vocabulary is only as good
   as its terms. This list is what the data voted for, not what the work needs.
2. **`bouwkundige eenheid` (469) — kenmerk or structure?** If a dossier genuinely
   spans several addresses as one structural unit, that may be a relationship
   between samples rather than a label on the dossier.
3. **Who owns the vocabulary?** Adding a term must be somebody's call, or it
   becomes tags in eighteen months.
4. **Why is `facade_scan_risk` empty on 863 of 864?** Worth knowing before adding
   two fields next to it.
5. **Does `eindbeoordeling` mean the same thing across suppliers?** If FundonService
   and FunderScan grade differently, one enum flattens a real difference.
