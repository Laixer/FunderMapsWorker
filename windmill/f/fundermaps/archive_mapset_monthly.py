# Archive one full-dataset GPKG per month: copy the earliest available
# analysis_full export of the current month from mapset/YYYY/mon/DD/ to
# mapset-archive/YYYY-MM/analysis_full.gpkg (kept forever). This is a
# redundant monthly snapshot, NOT a replacement for the dailies.
#
# DO NOT PRUNE mapset/. An earlier version of this comment said the nightly
# exports "are pruned after ~a month" -- that pruner was never built, and as of
# 2026-08-06 it must never be: the full daily series under mapset/ (702 days,
# 2.1 TB, back to 2024-08-19) is the ONLY raw material for building the history
# of the static model. The database keeps no model history. Deleted days cannot
# be reconstructed. Spaces has no versioning on this bucket -- deletes are final.
#
# Scheduled monthly on the 2nd so day 1's nightly export exists.
import datetime

import boto3
import wmill

MONTH_ABBR = ["jan", "feb", "mar", "apr", "may", "jun",
              "jul", "aug", "sep", "oct", "nov", "dec"]


def main(archive_bucket: str = "fundermaps-archive"):
    s3conf = wmill.get_resource("f/fundermaps/s3")
    endpoint = s3conf["endPoint"]
    if not endpoint.startswith("http"):
        endpoint = ("https://" if s3conf.get("useSSL", True) else "http://") + endpoint
    # NOT s3conf["bucket"] (that resource points at fundermaps-data, and other
    # scripts depend on it). The whole mapset/ + mapset-archive/ history moved
    # to the cold-storage bucket on 2026-08-07.
    bucket = archive_bucket

    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=s3conf["accessKey"],
        aws_secret_access_key=s3conf["secretKey"],
        region_name=s3conf.get("region") or "ams3",
    )

    now = datetime.datetime.now(datetime.timezone.utc)
    prefix = f"mapset/{now.year}/{MONTH_ABBR[now.month - 1]}/"

    days = []
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            parts = obj["Key"].split("/")
            if len(parts) == 5 and parts[4] == "analysis_full.gpkg":
                days.append((int(parts[3]), obj["Key"]))

    if not days:
        raise RuntimeError(f"no analysis_full.gpkg found under {prefix}")

    _, src = min(days)
    dst = f"mapset-archive/{now.year}-{now.month:02d}/analysis_full.gpkg"

    # Skip if this month's keeper already exists (idempotent re-runs).
    existing = client.list_objects_v2(Bucket=bucket, Prefix=dst)
    if existing.get("KeyCount", 0) > 0:
        return {"skipped": True, "existing": dst}

    # copy_object, NOT client.copy(): the latter is the TransferManager wrapper
    # and multiparts anything large, which a cold bucket rejects with
    # "BadDigest: The Content-Md5 you specified did not match what we received"
    # on CompleteMultipartUpload. A single-part CopyObject is capped at 5 GB and
    # analysis_full is ~3.34 GB; verified against the live bucket, ETag preserved.
    # Copies WITHIN one bucket are fine — Spaces cannot copy BETWEEN buckets.
    client.copy_object(CopySource={"Bucket": bucket, "Key": src},
                       Bucket=bucket, Key=dst)
    return {"archived": src, "to": dst}
