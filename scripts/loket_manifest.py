#!/usr/bin/env python3
"""Turn a FunderConsult loket export (Excel) into the manifest load-loket-export reads.

The export carries the melder's name, e-mail and address. None of that is needed to
bring the documents in, so none of it leaves this script: the manifest holds only the
melding's identifiers, its state, the reported BAG id, and one line per attachment.

    python3 scripts/loket_manifest.py export.xlsx manifest.tsv [--since 2026-04-01]

Selection (ClientApp #340, Don 2026-09-11): submitted on or after --since, and either
status Geverifieerd, or status "In behandeling" with phase closed. Everything else is
counted and left out.
"""
import argparse
import collections
import datetime as dt
import sys

import openpyxl

MELDING_COLS = ["Meldingsnummer", "Melding-ID", "Ingediend (UTC)", "Status", "Fase",
                "bag_nummeraanduiding_id", "intake_topics_label", "manual_request_category"]
BIJLAGE_COLS = ["Melding-ID", "Opslagsleutel", "Bestandsnaam", "Grootte (bytes)", "Bestandstype", "Categorie"]

HEADER = ["melding_nr", "melding_id", "submitted", "status", "fase", "bag_id", "topic", "request_category",
          "file_key", "file_name", "size", "mime", "category"]


def rows(ws):
    it = ws.iter_rows(values_only=True)
    header = [str(h) for h in next(it)]
    idx = {h: i for i, h in enumerate(header)}
    for r in it:
        if any(c is not None for c in r):
            yield lambda name, r=r: r[idx[name]] if name in idx else None


def clean(v):
    if v is None:
        return ""
    if isinstance(v, dt.datetime):
        return v.replace(microsecond=0).isoformat() + "Z"
    return str(v).replace("\t", " ").replace("\n", " ").strip()


def selected(status, fase, submitted, since):
    if submitted < since:
        return False
    return status == "Geverifieerd" or (status == "In behandeling" and fase == "closed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx")
    ap.add_argument("out")
    ap.add_argument("--since", default="2026-04-01")
    a = ap.parse_args()
    since = dt.datetime.fromisoformat(a.since)

    wb = openpyxl.load_workbook(a.xlsx, read_only=True, data_only=True)
    meldingen = {}
    skipped = collections.Counter()
    for g in rows(wb["Meldingen"]):
        submitted = g("Ingediend (UTC)")
        status, fase = clean(g("Status")), clean(g("Fase"))
        if not selected(status, fase, submitted, since):
            skipped[f"{status}/{fase}" if submitted >= since else "before --since"] += 1
            continue
        mid = clean(g("Melding-ID"))
        bag = clean(g("bag_nummeraanduiding_id"))
        bag = bag.replace("NL.IMBAG.NUMMERAANDUIDING.", "")
        if bag.startswith("NL.IMBAG.PAND."):
            bag = ""  # a pand is not an address; the loader records it as an exception
        meldingen[mid] = [clean(g("Meldingsnummer")), mid, clean(submitted), status, fase, bag,
                          clean(g("intake_topics_label")), clean(g("manual_request_category"))]

    n_files = 0
    with_files = set()
    with open(a.out, "w") as f:
        f.write("\t".join(HEADER) + "\n")
        for g in rows(wb["Bijlagen"]):
            mid = clean(g("Melding-ID"))
            if mid not in meldingen:
                continue
            n_files += 1
            with_files.add(mid)
            f.write("\t".join(meldingen[mid] + [clean(g("Opslagsleutel")), clean(g("Bestandsnaam")),
                                                 clean(g("Grootte (bytes)")), clean(g("Bestandstype")),
                                                 clean(g("Categorie"))]) + "\n")
        # Meldingen without attachments still get a dossier row, so the melding
        # itself is on record; the loader treats an empty file_key as "no file".
        for mid, m in meldingen.items():
            if mid not in with_files:
                f.write("\t".join(m + ["", "", "", "", ""]) + "\n")

    print(f"selected {len(meldingen)} meldingen, {n_files} attachment references -> {a.out}", file=sys.stderr)
    for k, n in skipped.most_common():
        print(f"  left out {n:5d}  {k}", file=sys.stderr)


if __name__ == "__main__":
    main()
