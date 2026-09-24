-- Production cluster / supercluster membership, to replicate the model-2024.1 cluster tiers
-- with TRAINING labels only (read-only).
\set QUIET on
SET max_parallel_workers_per_gather = 0;
\copy (SELECT bc.building_id, bc.cluster_id::text AS cluster_id, sc.supercluster_id::text AS supercluster_id FROM data.building_cluster bc LEFT JOIN data.supercluster sc ON sc.cluster_id = bc.cluster_id) TO STDOUT WITH CSV HEADER
