"""Bouwkundige eenheden voor heel Nederland, per gemeente (Don's regel variant 1, 2026-09-28).

Per gemeente-extract gm/<GMxxxx>.csv.gz (extract_gm.sh): naden = contouren >= 2,0 m binnen 0,25 m (kortste van beide
richtingen). Oordeel 'apart' bij (1) ander bouwjaar, (2) hoogteverschil > 0,5 m, (3) footprint-verhouding < 0,75,
(4) beide vastgesteld type en verschillend; ontbrekende waarde -> toets vervalt.
Eenheden = samenhangende componenten over 'samen'-naden, nooit over een grens van een huidig FunderMaps-cluster
(panden zonder cluster mogen onderling). Verschil met Schiedam-run: de naden worden van sterk (lang) naar zwak
samengevoegd en een samenvoeging die twee verschillende vastgestelde types in één eenheid zou brengen wordt
overgeslagen (Don 2026-09-28: 'knip bij het afwijkende rapport', de kettingfout). Naden over een gemeentegrens
worden niet bekeken.

Uitvoer: units.csv.gz (id, unit_id, gm) en naden.csv.gz (pand_a, pand_b, lengte_m, oordeel, reden), plus totalen.
"""
import glob
import os
import sys

import numpy as np
import pandas as pd
from shapely import STRtree, boundary, buffer, from_wkt, intersection, length

HERE = os.path.dirname(os.path.abspath(__file__))
# work dir with gm/*.csv.gz from extract_gm.sh; outputs land there too
os.chdir(os.environ.get('UNITS_WORK', HERE))


def run_gm(path):
    code = os.path.basename(path).split('.')[0]
    P = pd.read_csv(path)
    if P.empty:
        return None, None, {}
    geoms = from_wkt(P.wkt.values)
    bnd = boundary(geoms)
    tree = STRtree(geoms)
    ia, ib = tree.query(geoms, predicate='dwithin', distance=0.25)
    m = ia < ib
    ia, ib = ia[m], ib[m]
    la = length(intersection(bnd[ia], buffer(bnd[ib], 0.25)))
    lb = length(intersection(bnd[ib], buffer(bnd[ia], 0.25)))
    L = np.minimum(la, lb)
    keep = L >= 2.0
    ia, ib, L = ia[keep], ib[keep], L[keep]
    yr, h, area = P.yr.values.astype(float), P.height.values.astype(float), P.area.values.astype(float)
    ft = P.ft_est.values
    cl = P.cluster_id.values
    r1 = ~np.isnan(yr[ia]) & ~np.isnan(yr[ib]) & (yr[ia] != yr[ib])
    r2 = ~np.isnan(h[ia]) & ~np.isnan(h[ib]) & (np.abs(h[ia] - h[ib]) > 0.5)
    mx = np.fmax(area[ia], area[ib])
    r3 = ~np.isnan(area[ia]) & ~np.isnan(area[ib]) & (mx > 0) & (np.fmin(area[ia], area[ib]) / np.where(mx > 0, mx, 1) < 0.75)
    fa, fb = pd.Series(ft[ia]), pd.Series(ft[ib])
    r4 = (fa.notna() & fb.notna() & (fa != fb)).values
    apart = r1 | r2 | r3 | r4
    ca, cb = pd.Series(cl[ia]), pd.Series(cl[ib])
    same_cl = ((ca.notna() & cb.notna() & (ca == cb)) | (ca.isna() & cb.isna())).values

    # union-find, strongest seams first, never joining two different established types
    parent = np.arange(len(P))
    est = {i: {ft[i]} for i in range(len(P)) if isinstance(ft[i], str)}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    skipped_conflict = 0
    for k in np.argsort(-L):
        if apart[k] or not same_cl[k]:
            continue
        a, b = find(ia[k]), find(ib[k])
        if a == b:
            continue
        ea, eb = est.get(a, set()), est.get(b, set())
        if ea and eb and ea != eb:
            skipped_conflict += 1
            continue
        parent[a] = b
        if ea or eb:
            est[b] = ea | eb
    roots = np.array([find(i) for i in range(len(P))])
    U = pd.DataFrame({'id': P.id.values, 'unit_id': [f'{code}:{r}' for r in roots], 'gm': code, 'cluster_id': cl})
    reason = np.array([','.join(str(n) for n, f in zip((1, 2, 3, 4), fl) if f) for fl in zip(r1, r2, r3, r4)], dtype=object) if len(ia) else np.array([])
    S = pd.DataFrame({'pand_a': np.minimum(P.id.values[ia], P.id.values[ib]), 'pand_b': np.maximum(P.id.values[ia], P.id.values[ib]),
                      'lengte_m': L.round(2), 'oordeel': np.where(apart, 'apart', 'samen'), 'reden': reason, 'gm': code})
    stats = dict(gm=code, panden=len(P), naden=len(S), samen=int((~apart).sum()), apart=int(apart.sum()), r1=int(r1.sum()), r2=int(r2.sum()),
                 r3=int(r3.sum()), r4=int(r4.sum()), over_clustergrens=int((~apart & ~same_cl).sum()), keten_geknipt=skipped_conflict,
                 eenheden=int(U.unit_id.nunique()))
    return U, S, stats


if __name__ == '__main__':
    files = sorted(glob.glob('gm/*.csv.gz'))
    if len(sys.argv) > 1:
        files = [f for f in files if os.path.basename(f).split('.')[0] in sys.argv[1:]]
    us, ss, st = [], [], []
    for i, f in enumerate(files):
        U, S, stats = run_gm(f)
        if U is None:
            continue
        us.append(U); ss.append(S); st.append(stats)
        print(i + 1, len(files), stats, flush=True)
    pd.concat(us).to_csv('units.csv.gz', index=False)
    pd.concat(ss).to_csv('naden.csv.gz', index=False)
    T = pd.DataFrame(st)
    T.to_csv('stats_per_gm.csv', index=False)
    print(T.drop(columns='gm').sum().to_string())
