"""Latency summary of a load log: python3 -I latency.py out/<run>.load.log [HH:MM:SS-from] [HH:MM:SS-to]"""
import re
import sys

path = sys.argv[1]
lo = sys.argv[2] if len(sys.argv) > 2 else "00:00:00"
hi = sys.argv[3] if len(sys.argv) > 3 else "99:99:99"
pat = re.compile(r"^(\d\d:\d\d:\d\d) ins +(\d+) err (\d+) max +(\d+) ms \S read +(\d+) err (\d+) max +(\d+) ms")
rows = []
for line in open(path):
    m = pat.match(line)
    if m and lo <= m.group(1) <= hi:
        t, ins, ie, imax, rd, re_, rmax = m.groups()
        rows.append((t, int(ins), int(ie), int(imax), int(rd), int(re_), int(rmax)))
if not rows:
    print("no seconds in range")
    sys.exit()
print(f"{len(rows)} seconds {rows[0][0]}..{rows[-1][0]}: inserts {sum(r[1] for r in rows)} (errors {sum(r[2] for r in rows)}), reads {sum(r[4] for r in rows)} (errors {sum(r[5] for r in rows)})")
print(f"worst insert {max(r[3] for r in rows)} ms, worst read {max(r[6] for r in rows)} ms")
for limit in (250, 500, 1000, 2000):
    print(f"  seconds with something slower than {limit} ms: {sum(1 for r in rows if r[3] > limit or r[6] > limit)}")
worst = sorted(rows, key=lambda r: max(r[3], r[6]), reverse=True)[:5]
print("slowest seconds:", ", ".join(f"{r[0]} ({max(r[3], r[6])} ms)" for r in worst))
