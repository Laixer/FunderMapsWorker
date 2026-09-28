"""Post-process model-2026.2: one foundation type per building cluster (Don, 2026-09-28).

Input : out/model_foundation_2026_2.csv.gz (train_predict.py) and ../data/clusters.csv.gz (sql/04_clusters.sql)
Output: out/model_foundation_2026_2.csv.gz, rewritten in place (same columns); the unpooled file is kept as
        out/model_foundation_2026_2.unpooled.csv.gz

Why: panden in one cluster (DBSCAN on geometry, construction year and height: one building project) share their
foundation. Report labels inside a cluster agree 99.7% of the time (32,505 clusters with >= 2 labels, 99.0% fully
homogeneous). The model, however, scores every pand on its own, so a row with near-equal probabilities flips type
from house to house (Gouda, Kamperfoelielaan 65-79: p ~ 1/3 each).

Rules, for panden whose source is 'model' (own evidence is never touched):
  1. the cluster holds own evidence (report or reliable QuickScan): take the evidence's majority foundation type;
     grade becomes at least 'betrouwbaar' (source stays 'model'). 94.8% of such panden already agreed.
  2. otherwise: average the blend probabilities and p_oplanger over the cluster's model panden and re-take the
     argmax, so the whole cluster gets one type; confidence = the pooled maximum, grade unchanged.
Out-of-sample (reliability/24_cluster_pool.py): pooling keeps accuracy (pool R+G 76.6 -> 76.8, held-out
municipalities 74.1 -> 74.4, Utrecht 79.6 -> 79.5).
"""
import os
import shutil

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out', 'model_foundation_2026_2.csv.gz')
RAW = os.path.join(HERE, 'out', 'model_foundation_2026_2.unpooled.csv.gz')
CLUSTERS = os.path.join(os.path.dirname(HERE), 'data', 'clusters.csv.gz')
FAM = ['wood', 'no_pile', 'concrete']
GRADE_RANK = {'zwak': 0, 'redelijk': 1, 'betrouwbaar': 2, 'zeer betrouwbaar': 3, 'vastgesteld': 4}


def main():
    if not os.path.exists(RAW):
        shutil.copyfile(OUT, RAW)
    d = pd.read_csv(RAW)
    cl = pd.read_csv(CLUSTERS, usecols=['building_id', 'cluster_id']).drop_duplicates('building_id')
    d = d.merge(cl, on='building_id', how='left')
    model = (d.source == 'model') & d.cluster_id.notna()

    # 1. clusters with own evidence -> the evidence's majority type
    ev = d[(d.source != 'model') & d.cluster_id.notna()]
    maj = ev.groupby('cluster_id').foundation_type.agg(lambda s: s.value_counts().index[0])
    hit = model & d.cluster_id.isin(maj.index)
    ft = d.loc[hit, 'cluster_id'].map(maj)
    ev_changed = int((ft.values != d.loc[hit, 'foundation_type'].values).sum())
    d.loc[hit, 'foundation_type'] = ft.values
    d.loc[hit, 'family'] = np.where(ft.values == 'wood_charger', 'wood', ft.values)
    up = hit & (d.grade.map(GRADE_RANK) < GRADE_RANK['betrouwbaar'])
    d.loc[up, 'grade'] = 'betrouwbaar'

    # 2. the rest: pool probabilities over the cluster's model panden
    rest = model & ~hit
    cols = ['p_wood', 'p_no_pile', 'p_concrete', 'p_oplanger']
    pooled = d[rest].groupby('cluster_id')[cols].transform('mean')
    P = pooled[['p_wood', 'p_no_pile', 'p_concrete']].values
    fam = np.array(FAM)[P.argmax(1)]
    ft2 = np.where(fam == 'wood', np.where(pooled.p_oplanger.values >= 0.5, 'wood_charger', 'wood'), fam)
    changed = int((ft2 != d.loc[rest, 'foundation_type'].values).sum())
    d.loc[rest, cols] = pooled.round(3).values
    d.loc[rest, 'family'] = fam
    d.loc[rest, 'foundation_type'] = ft2
    d.loc[rest, 'confidence'] = P.max(1).round(3)

    d.drop(columns='cluster_id').to_csv(OUT, index=False, compression='gzip')
    print(f'clusters with evidence: {hit.sum():,} model panden set to the evidence majority, {ev_changed:,} changed type')
    print(f'pooled: {rest.sum():,} model panden in clusters, {changed:,} changed type')
    print(d.foundation_type.value_counts().to_string())


if __name__ == '__main__':
    main()
