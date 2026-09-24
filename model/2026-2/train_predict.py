"""Foundation-type model 2026.2 ("M6c") -- train once on ALL labels, score ALL panden.

Production packaging of the winning method from the 2026-09-24 study (../scripts/30_models.py, M6c):
LightGBM multiclass (wood / no_pile / concrete) on
  - pand attributes + vendor soil / groundwater / pleistocene / subsidence
  - label-free context: 200 m grid 3x3 window (ctx_*), buurt aggregates, RD x/y
  - label-derived: kNN label shares (knn_*, near10_*), buurt x era label counts (be_*), cluster label shares (cl_*)
Label-derived features of the TRAINING rows are computed report-grouped leave-one-out (a row never sees
labels from its own inquiry), exactly as in the study. Every pand is then scored with label features built
from ALL labels.

Inputs  (read-only local extracts, see README.md for the SQL that makes them):
  ../data/buildings.csv.gz   all panden with model inputs     (sql/02_buildings.sql)
  ../data/samples.csv        all foundation-type samples      (sql/01_samples.sql)
  ../data/clusters.csv.gz    production cluster membership    (sql/04_clusters.sql)
Outputs:
  out/model_foundation_2026_2.csv.gz   building_id,p_wood,p_no_pile,p_concrete,family,confidence,evidence
  out/model_foundation_2026_2.lgb      LightGBM model (+ .meta.json with features, soil codes, params)
  work/                                intermediate parquet (safe to delete)

Usage:  .venv/bin/python prod/train_predict.py [--label-date YYYY-MM-DD] [--rebuild]
Never touches Postgres.
"""
import argparse
import datetime as dt
import hashlib
import json
import multiprocessing
import os
import resource
import time
import warnings

warnings.filterwarnings('ignore', category=RuntimeWarning)

import duckdb
import lightgbm as lgb
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from scipy.spatial import cKDTree

T0 = float(os.environ.setdefault('FT_T0', str(time.time())))  # shared with the DuckDB child process
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, 'data')
WORK = os.path.join(HERE, 'work')
OUT = os.path.join(HERE, 'out')
MODEL_NAME = 'model_foundation_2026_2'

FAM = ['wood', 'no_pile', 'concrete']
CHUNK = 1_000_000
KNN_CHUNK = 500_000
# kNN / weighting constants -- identical to 30_models.py knn_feats()
K, D0, T0_CY, CY_FILL = 30, 200.0, 15.0, 1950.0
LOCAL_RADIUS_M = 250.0
MUNICIPAL_MIN_LABELS = 30

LGB_BASE = ['cy', 'height', 'address_count', 'ground_level', 'surface_area', 'soil_cat', 'gw_level',
            'pleistocene_depth', 'subsidence_velocity',
            'ctx_density', 'ctx_mean_cy', 'ctx_share_pre1930', 'ctx_share_pre1965', 'ctx_mean_height',
            'buurt_n', 'buurt_median_cy', 'buurt_share_pre1930', 'buurt_mean_ground_level', 'buurt_mean_height']
LGB_FULL = LGB_BASE + ['x', 'y', 'knn_W', 'knn_d1', 'knn_d10', 'knn_p_wood', 'knn_p_nopile', 'knn_p_concrete',
                       'near10_wood', 'near10_nopile', 'near10_concrete',
                       'be_n', 'be_wood', 'be_nopile', 'cl_n', 'cl_wood', 'cl_nopile']
LABEL_FEATS = LGB_FULL[len(LGB_BASE) + 2:]
PARAMS = dict(objective='multiclass', num_class=3, learning_rate=0.05, num_leaves=63, min_data_in_leaf=50,
              feature_fraction=0.8, bagging_fraction=0.8, bagging_freq=1, lambda_l2=1.0, verbose=-1, num_threads=4)


def log(msg):
    rss = max(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss) / 1024 / 1024
    print(f'[{time.time() - T0:7.1f}s | peak {rss:4.2f} GB] {msg}', flush=True)


# ---------------------------------------------------------------------------------------------- stage A (DuckDB)
def build_base(label_date, rebuild):
    """All label-free features + label/cluster keys + buurt x era / cluster label counts -> work/base.parquet."""
    base = os.path.join(WORK, 'base.parquet')
    if os.path.exists(base) and not rebuild:
        log(f'reusing {base} (pass --rebuild to recompute)')
        return base
    os.makedirs(os.path.join(WORK, 'tmp'), exist_ok=True)
    con = duckdb.connect()
    con.execute(f"PRAGMA memory_limit='3GB'; PRAGMA threads=4; PRAGMA temp_directory='{WORK}/tmp';"
                "SET preserve_insertion_order=false; SET enable_progress_bar=false")
    # --- labels: one leading sample per pand (verbatim port of scripts/10_labels.py) -----------------
    con.execute(f"""
    CREATE TABLE s AS SELECT * FROM read_csv_auto('{DATA}/samples.csv', header=true);
    CREATE TABLE fam AS SELECT * FROM (VALUES
     ('wood','wood'),('wood_charger','wood'),('wood_amsterdam','wood'),('wood_rotterdam','wood'),
     ('wood_rotterdam_amsterdam','wood'),('wood_amsterdam_arch','wood'),('wood_rotterdam_arch','wood'),
     ('no_pile','no_pile'),('no_pile_masonry','no_pile'),('no_pile_strips','no_pile'),('no_pile_concrete_floor','no_pile'),
     ('no_pile_slit','no_pile'),('no_pile_bearing_floor','no_pile'),
     ('concrete','concrete'),('weighted_pile','concrete'),('steel_pile','concrete'),
     ('combined','other'),('other','other')) t(foundation_type, family);
    CREATE TABLE elig AS
    SELECT s.*, f.family,
      CASE inquiry_type WHEN 'foundation_research' THEN 0 WHEN 'inspectionpit' THEN 1 WHEN 'second_opinion' THEN 2
        WHEN 'note' THEN 3 WHEN 'additional_research' THEN 4 WHEN 'demolition_research' THEN 5
        WHEN 'architectural_research' THEN 6 WHEN 'archive_research' THEN 7 ELSE 100 END AS type_rank
    FROM s JOIN fam f USING (foundation_type)
    WHERE NOT sample_deleted AND NOT inquiry_deleted AND inquiry_type NOT IN ('quickscan', 'facade_scan')
      AND document_date <= DATE '{label_date}'
      AND (bag_built_year IS NULL OR document_date >= make_date(bag_built_year - 5, 1, 1));
    CREATE TABLE lab AS
    SELECT building_id, CASE family WHEN 'wood' THEN 0 WHEN 'no_pile' THEN 1 ELSE 2 END AS yv, inquiry_id
    FROM (SELECT *, row_number() OVER (PARTITION BY building_id ORDER BY type_rank, document_date DESC, sample_id DESC) rn
          FROM elig) WHERE rn = 1 AND family <> 'other';
    DROP TABLE s; DROP TABLE elig;
    """)
    log('labels built: ' + str(con.sql('SELECT count(*) FROM lab').fetchone()[0]))
    # --- buildings + label-free context (verbatim port of scripts/20_features.py) ------------------
    con.execute(f"""
    CREATE TABLE b AS SELECT * FROM read_csv('{DATA}/buildings.csv.gz', header=true, columns={{
     'building_id':'VARCHAR','cy':'INTEGER','height':'DOUBLE','address_count':'INTEGER','ground_level':'DOUBLE',
     'surface_area':'DOUBLE','soil':'VARCHAR','gw_level':'DOUBLE','pleistocene_depth':'DOUBLE','subsidence_velocity':'DOUBLE',
     'buurt':'VARCHAR','wijk':'VARCHAR','gm_code':'VARCHAR','gm_name':'VARCHAR','x':'DOUBLE','y':'DOUBLE','tree_type':'VARCHAR'}});
    CREATE TABLE cell AS SELECT floor(x/200)::INT gx, floor(y/200)::INT gy, count(*) n, count(cy) ncy, sum(cy) scy,
      count(*) FILTER (WHERE cy < 1930) n1930, count(*) FILTER (WHERE cy < 1965) n1965, sum(height) sh, count(height) nh
    FROM b WHERE x IS NOT NULL GROUP BY 1,2;
    CREATE TABLE ctx AS
    SELECT o.gx + dx AS gx, o.gy + dy AS gy, sum(o.n) n, sum(o.ncy) ncy, sum(o.scy) scy, sum(o.n1930) n1930,
           sum(o.n1965) n1965, sum(o.sh) sh, sum(o.nh) nh
    FROM cell o, (SELECT unnest([-1,0,1]) dx), (SELECT unnest([-1,0,1]) dy) GROUP BY 1,2;
    CREATE TABLE bu AS SELECT buurt, count(*) buurt_n, median(cy) buurt_median_cy,
      avg((cy<1930)::INT) buurt_share_pre1930, avg(ground_level) buurt_mean_ground_level, avg(height) buurt_mean_height
    FROM b WHERE buurt IS NOT NULL GROUP BY 1;
    CREATE TABLE clu AS SELECT building_id, min(cluster_id) cluster_id
      FROM read_csv('{DATA}/clusters.csv.gz', header=true, all_varchar=true) GROUP BY 1;
    CREATE TABLE soil_codes AS SELECT s AS soil_k, (row_number() OVER (ORDER BY s) - 1)::INT soil_cat
      FROM (SELECT DISTINCT coalesce(soil, 'NA') s FROM b);
    """)
    log('buildings loaded: ' + str(con.sql('SELECT count(*) FROM b').fetchone()[0]))
    # era bins = pd.cut(cy, [-1e9,1700,1800,1880,1900,1920,1930,1940,1950,1965,1975,1990,1e9], right=False), NULL -> -1
    con.execute("""
    CREATE TABLE f AS
    SELECT b.building_id, b.cy, b.height, b.address_count, b.ground_level, b.surface_area, sc.soil_cat,
      b.gw_level, b.pleistocene_depth, b.subsidence_velocity, b.x, b.y, b.buurt, b.gm_code,
      CASE WHEN b.cy IS NULL THEN -1 WHEN b.cy < 1700 THEN 0 WHEN b.cy < 1800 THEN 1 WHEN b.cy < 1880 THEN 2
           WHEN b.cy < 1900 THEN 3 WHEN b.cy < 1920 THEN 4 WHEN b.cy < 1930 THEN 5 WHEN b.cy < 1940 THEN 6
           WHEN b.cy < 1950 THEN 7 WHEN b.cy < 1965 THEN 8 WHEN b.cy < 1975 THEN 9 WHEN b.cy < 1990 THEN 10
           ELSE 11 END AS era,
      ctx.n/9.0 AS ctx_density, ctx.scy/nullif(ctx.ncy,0) AS ctx_mean_cy, ctx.n1930/ctx.n::DOUBLE AS ctx_share_pre1930,
      ctx.n1965/ctx.n::DOUBLE AS ctx_share_pre1965, ctx.sh/nullif(ctx.nh,0) AS ctx_mean_height,
      bu.buurt_n, bu.buurt_median_cy, bu.buurt_share_pre1930, bu.buurt_mean_ground_level, bu.buurt_mean_height,
      clu.cluster_id, lab.yv, lab.inquiry_id
    FROM b
    JOIN soil_codes sc ON sc.soil_k = coalesce(b.soil, 'NA')
    LEFT JOIN lab USING (building_id)
    LEFT JOIN clu USING (building_id)
    LEFT JOIN ctx ON ctx.gx = floor(b.x/200)::INT AND ctx.gy = floor(b.y/200)::INT
    LEFT JOIN bu USING (buurt);
    DROP TABLE b; DROP TABLE cell; DROP TABLE ctx; DROP TABLE bu; DROP TABLE clu;
    """)
    # label counts per buurt x era, per cluster, per municipality (ALL labels) and per key x inquiry
    # (the part a training row must not see: its own report).
    con.execute("""
    CREATE TABLE be AS SELECT buurt, era, count(*) FILTER (WHERE yv=0) c0, count(*) FILTER (WHERE yv=1) c1,
      count(*) FILTER (WHERE yv=2) c2 FROM f WHERE yv IS NOT NULL AND buurt IS NOT NULL GROUP BY 1,2;
    CREATE TABLE beq AS SELECT buurt, era, inquiry_id, count(*) FILTER (WHERE yv=0) c0, count(*) FILTER (WHERE yv=1) c1,
      count(*) FILTER (WHERE yv=2) c2 FROM f WHERE yv IS NOT NULL AND buurt IS NOT NULL GROUP BY 1,2,3;
    CREATE TABLE cl AS SELECT cluster_id, count(*) FILTER (WHERE yv=0) c0, count(*) FILTER (WHERE yv=1) c1,
      count(*) FILTER (WHERE yv=2) c2 FROM f WHERE yv IS NOT NULL AND cluster_id IS NOT NULL GROUP BY 1;
    CREATE TABLE clq AS SELECT cluster_id, inquiry_id, count(*) FILTER (WHERE yv=0) c0, count(*) FILTER (WHERE yv=1) c1,
      count(*) FILTER (WHERE yv=2) c2 FROM f WHERE yv IS NOT NULL AND cluster_id IS NOT NULL GROUP BY 1,2;
    CREATE TABLE gm AS SELECT gm_code, count(*) gm_nlab FROM f WHERE yv IS NOT NULL AND gm_code IS NOT NULL GROUP BY 1;
    """)
    con.execute(f"""
    COPY (
    SELECT (row_number() OVER (ORDER BY f.building_id) - 1)::INT AS rid, f.building_id,
      f.cy, f.height, f.address_count, f.ground_level, f.surface_area, f.soil_cat, f.gw_level, f.pleistocene_depth,
      f.subsidence_velocity, f.ctx_density, f.ctx_mean_cy, f.ctx_share_pre1930, f.ctx_share_pre1965, f.ctx_mean_height,
      f.buurt_n, f.buurt_median_cy, f.buurt_share_pre1930, f.buurt_mean_ground_level, f.buurt_mean_height, f.x, f.y,
      f.yv::TINYINT AS yv, f.inquiry_id,
      coalesce(be.c0,0)::INT be_c0, coalesce(be.c1,0)::INT be_c1, coalesce(be.c2,0)::INT be_c2,
      coalesce(beq.c0,0)::INT beq_c0, coalesce(beq.c1,0)::INT beq_c1, coalesce(beq.c2,0)::INT beq_c2,
      coalesce(cl.c0,0)::INT cl_c0, coalesce(cl.c1,0)::INT cl_c1, coalesce(cl.c2,0)::INT cl_c2,
      coalesce(clq.c0,0)::INT clq_c0, coalesce(clq.c1,0)::INT clq_c1, coalesce(clq.c2,0)::INT clq_c2,
      coalesce(gm.gm_nlab,0)::INT gm_nlab
    FROM f
    LEFT JOIN be ON be.buurt = f.buurt AND be.era = f.era
    LEFT JOIN beq ON beq.buurt = f.buurt AND beq.era = f.era AND beq.inquiry_id = f.inquiry_id
    LEFT JOIN cl ON cl.cluster_id = f.cluster_id
    LEFT JOIN clq ON clq.cluster_id = f.cluster_id AND clq.inquiry_id = f.inquiry_id
    LEFT JOIN gm ON gm.gm_code = f.gm_code
    ORDER BY rid
    ) TO '{base}' (FORMAT parquet, ROW_GROUP_SIZE 1000000);
    COPY soil_codes TO '{WORK}/soil_codes.csv' (HEADER);
    """)
    con.close()
    log(f'wrote {base}')
    return base


# ---------------------------------------------------------------------------------------------- stage B (features)
def knn_block(tree, Y, cy_tr, inq_tr, xy, cy, self_idx=None, inq=None):
    """kNN label features, same maths as 30_models.py knn_feats(). self_idx/inq given -> training rows:
    drop self and every neighbour from the same inquiry (report-grouped LOO, K+60 candidates)."""
    grp = inq is not None
    d, idx = tree.query(xy, k=K + (60 if grp else 0), workers=4)
    valid = np.ones_like(d, bool)
    if grp:
        valid &= idx != self_idx[:, None]
        valid &= inq_tr[idx] != inq[:, None]
    valid &= np.cumsum(valid, 1) <= K
    Yn = Y[idx]                                            # (n, k, 3)
    dcy = np.abs(cy_tr[idx] - cy[:, None])
    w = np.exp(-d / D0) * np.exp(-dcy / T0_CY) * valid
    cnt = (w[:, :, None] * Yn).sum(1)
    W = w.sum(1)
    first10 = valid & (np.cumsum(valid, 1) <= 10)
    near10 = (Yn * first10[:, :, None]).sum(1) / np.maximum(first10.sum(1), 1)[:, None]
    dm = np.where(valid, d, np.inf)
    d1 = dm.min(1)
    s10 = np.sort(dm, 1)[:, :10]
    s10[~np.isfinite(s10)] = np.nan
    with np.errstate(all='ignore'):
        d10 = np.nanmedian(s10, 1)
        pk = cnt / np.maximum(W, 1e-9)[:, None]
    pk[W < 1e-6] = np.nan
    return np.column_stack([W, d1, d10, pk, near10]).astype(np.float32)   # knn_W,d1,d10,p*3,near10*3


def share_feats(c):
    n = c.sum(1)
    with np.errstate(invalid='ignore', divide='ignore'):
        return np.column_stack([n, np.where(n > 0, c[:, 0] / n, np.nan), np.where(n > 0, c[:, 1] / n, np.nan)]).astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label-date', default=dt.date.today().isoformat(), help='ignore samples documented after this date')
    ap.add_argument('--rebuild', action='store_true', help='recompute work/base.parquet')
    args = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)

    # DuckDB stage in a child process so its memory is returned before the numpy stage starts
    ctx = multiprocessing.get_context('spawn')
    pr = ctx.Process(target=build_base, args=(args.label_date, args.rebuild))
    pr.start()
    pr.join()
    if pr.exitcode != 0:
        raise SystemExit(f'build_base failed with exit code {pr.exitcode}')
    base = os.path.join(WORK, 'base.parquet')

    # read column by column straight into float32 to keep the peak low
    pf = pq.ParquetFile(base)
    N = pf.metadata.num_rows
    rd = lambda c: pf.read(columns=[c]).column(0).to_numpy(zero_copy_only=False)
    num_cols = LGB_BASE + ['x', 'y']
    X = np.empty((N, len(LGB_FULL)), np.float32)           # the full feature matrix, all-label version
    col = {c: i for i, c in enumerate(LGB_FULL)}
    for c in num_cols:
        X[:, col[c]] = rd(c)
    yv = rd('yv').astype(np.float32)
    labelled = ~np.isnan(yv)
    lab_idx = np.where(labelled)[0]
    y_lab = yv[labelled].astype(np.int64)
    del yv
    inq_lab = rd('inquiry_id')[labelled].astype(np.int64)
    gm_nlab = rd('gm_nlab')
    xy_all = np.column_stack([rd('x'), rd('y')]).astype(np.float64)
    log(f'loaded {N:,} panden, {labelled.sum():,} labelled '
        f'(wood {np.sum(y_lab == 0):,} / no_pile {np.sum(y_lab == 1):,} / concrete {np.sum(y_lab == 2):,})')

    # buurt x era + cluster label features: all labels for everyone, report-grouped LOO for the training rows
    L = np.empty((len(lab_idx), len(LABEL_FEATS)), np.float32)
    lc = {c: i for i, c in enumerate(LABEL_FEATS)}
    for pre, q in [('be', 'beq'), ('cl', 'clq')]:
        c_all = np.column_stack([rd(f'{pre}_c{i}') for i in range(3)]).astype(np.float64)
        c_q = np.column_stack([rd(f'{q}_c{i}')[lab_idx] for i in range(3)]).astype(np.float64)
        X[:, col[f'{pre}_n']:col[f'{pre}_n'] + 3] = share_feats(c_all)
        L[:, lc[f'{pre}_n']:lc[f'{pre}_n'] + 3] = share_feats(c_all[lab_idx] - c_q)
        del c_all, c_q
    be_n_all = X[:, col['be_n']].copy()
    del pf

    # kNN over the labelled panden
    cy_all = X[:, col['cy']].astype(np.float64)
    cy_all[np.isnan(cy_all)] = CY_FILL
    tree = cKDTree(xy_all[lab_idx])
    Y = np.eye(3)[y_lab]
    cy_tr = cy_all[lab_idx]
    k0 = col['knn_W']
    for s in range(0, N, KNN_CHUNK):
        e = min(s + KNN_CHUNK, N)
        X[s:e, k0:k0 + 9] = knn_block(tree, Y, cy_tr, inq_lab, xy_all[s:e], cy_all[s:e])
        log(f'kNN all labels {e:,}/{N:,}')
    for s in range(0, len(lab_idx), 200_000):
        e = min(s + 200_000, len(lab_idx))
        L[s:e, 0:9] = knn_block(tree, Y, cy_tr, inq_lab, xy_all[lab_idx[s:e]], cy_all[lab_idx[s:e]],
                                self_idx=np.arange(s, e), inq=inq_lab[s:e])
    log('kNN report-grouped LOO for training rows done')
    del xy_all, cy_all, tree

    # training matrix = label-free part of X + LOO label features
    Xtr = X[lab_idx].copy()
    Xtr[:, col[LABEL_FEATS[0]]:] = L
    del L

    # ------------------------------------------------------------------------------------------ train
    va = np.array([int(hashlib.md5(('v' + str(v)).encode()).hexdigest()[:8], 16) % 10 == 0 for v in inq_lab])
    cat = [col['soil_cat']]
    dtr = lgb.Dataset(Xtr[~va], y_lab[~va], feature_name=LGB_FULL, categorical_feature=cat, free_raw_data=True)
    dva = lgb.Dataset(Xtr[va], y_lab[va], feature_name=LGB_FULL, categorical_feature=cat, reference=dtr)
    ev = {}
    mdl = lgb.train(PARAMS, dtr, 2000, valid_sets=[dva],
                    callbacks=[lgb.early_stopping(50, verbose=False), lgb.record_evaluation(ev)])
    best = mdl.best_iteration
    log(f'trained: {(~va).sum():,} train / {va.sum():,} validation rows (inquiry-grouped), best_iteration {best}, '
        f'val multi_logloss {ev["valid_0"]["multi_logloss"][best - 1]:.4f}')
    mpath = os.path.join(OUT, MODEL_NAME + '.lgb')
    mdl.save_model(mpath, num_iteration=best)
    soil = pd.read_csv(os.path.join(WORK, 'soil_codes.csv'))
    json.dump(dict(model=MODEL_NAME, features=LGB_FULL, categorical=['soil_cat'],
                   soil_codes=dict(zip(soil.soil_k, soil.soil_cat.astype(int))), params=PARAMS, best_iteration=best,
                   n_train=int((~va).sum()), n_valid=int(va.sum()), label_date=args.label_date,
                   knn=dict(K=K, d0=D0, t0=T0_CY, cy_fill=CY_FILL),
                   evidence=dict(local_radius_m=LOCAL_RADIUS_M, municipal_min_labels=MUNICIPAL_MIN_LABELS),
                   trained_at=dt.datetime.now().isoformat(timespec='seconds')),
              open(os.path.join(OUT, MODEL_NAME + '.meta.json'), 'w'), indent=1)

    # in-sample sanity (training-style features): catches wiring bugs, NOT an accuracy estimate
    p_loo = mdl.predict(Xtr, num_iteration=best)
    del Xtr, dtr, dva

    # ------------------------------------------------------------------------------------------ predict
    P = np.empty((N, 3), np.float32)
    for s in range(0, N, CHUNK):
        e = min(s + CHUNK, N)
        P[s:e] = mdl.predict(X[s:e], num_iteration=best)
        log(f'predict {e:,}/{N:,}')

    # evidence tier
    local = (be_n_all >= 1) | (X[:, col['knn_d1']] <= LOCAL_RADIUS_M)
    municipal = gm_nlab >= MUNICIPAL_MIN_LABELS
    evidence = np.where(local, 0, np.where(municipal, 1, 2)).astype(np.int8)
    del X

    # probabilities in thousandths that sum to exactly 1000 (largest remainder)
    raw = P.astype(np.float64) * 1000
    q = np.floor(raw).astype(np.int32)
    rem = raw - q
    short = 1000 - q.sum(1)
    order = np.argsort(-rem, 1)
    for r in range(3):
        add = short > r
        q[np.arange(N)[add], order[add, r]] += 1
    fam = P.argmax(1).astype(np.int8)
    conf = q[np.arange(N), fam]
    pd.DataFrame({'rid': np.arange(N, dtype=np.int32), 'p_wood': q[:, 0], 'p_no_pile': q[:, 1], 'p_concrete': q[:, 2],
                  'fam': fam, 'conf': conf, 'ev': evidence}).to_parquet(os.path.join(WORK, 'pred.parquet'), index=False)

    out = os.path.join(OUT, MODEL_NAME + '.csv.gz')
    con = duckdb.connect()
    con.execute(f"PRAGMA memory_limit='2GB'; PRAGMA threads=4; PRAGMA temp_directory='{WORK}/tmp'; SET enable_progress_bar=false")
    con.execute(f"""
    COPY (
      SELECT b.building_id, (p.p_wood / 1000.0)::DECIMAL(4,3) AS p_wood, (p.p_no_pile / 1000.0)::DECIMAL(4,3) AS p_no_pile,
        (p.p_concrete / 1000.0)::DECIMAL(4,3) AS p_concrete,
        ['wood','no_pile','concrete'][p.fam + 1] AS family, (p.conf / 1000.0)::DECIMAL(4,3) AS confidence,
        ['local','municipal','none'][p.ev + 1] AS evidence
      FROM read_parquet('{WORK}/pred.parquet') p JOIN read_parquet('{base}') b USING (rid) ORDER BY p.rid
    ) TO '{out}' (FORMAT csv, HEADER, COMPRESSION gzip);
    """)
    log(f'wrote {out}')

    # ------------------------------------------------------------------------------------------ report
    print('\nrows written:', N)
    print('\nfamily (argmax):')
    print(pd.Series(fam).map(dict(enumerate(FAM))).value_counts().rename('panden').to_frame()
          .assign(pct=lambda d: (100 * d.panden / N).round(1)).to_string())
    print('\nevidence tier:')
    evs = pd.Series(evidence).map({0: 'local', 1: 'municipal', 2: 'none'})
    print(evs.value_counts().rename('panden').to_frame().assign(pct=lambda d: (100 * d.panden / N).round(1)).to_string())
    print('\nfamily x evidence (row %):')
    print((pd.crosstab(evs, pd.Series(fam).map(dict(enumerate(FAM))), normalize='index') * 100).round(1).to_string())
    print('\nmean p per evidence tier:')
    print(pd.DataFrame(P, columns=FAM).groupby(evs.values).mean().round(3).to_string())

    print('\nSANITY (IN-SAMPLE, labelled panden -- not an accuracy estimate):')
    for name, pp in [('scored output (all-label features, own label visible)', P[lab_idx]),
                     ('training features (report-grouped LOO)', p_loo)]:
        pr = pp.argmax(1)
        print(f'  {name}: accuracy {np.mean(pr == y_lab):.3f}, mean p_wood {pp[:, 0].mean():.3f} vs observed {np.mean(y_lab == 0):.3f}')
        print('   ', pd.crosstab(pd.Series(y_lab).map(dict(enumerate(FAM))).rename('label'),
                                pd.Series(pr).map(dict(enumerate(FAM))).rename('pred')).to_string().replace('\n', '\n    '))
    log('done')


if __name__ == '__main__':
    main()
