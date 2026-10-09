# Windmill worker image (Windmill + GDAL)

The stock `ghcr.io/windmill-labs/windmill` image plus `gdal-bin`, so Windmill
scripts can run `ogr2ogr`. It exists for the nightly GPKG export
(`process_mapset` → `fundermaps-archive/mapset/<date>/<tileset>.gpkg`), which is
moving off the queue worker droplet (`fundermaps-worker-0`) so that droplet can
be retired.

## Where it runs

Droplet `fundermaps-windmill-worker-0`, rootful Podman, as the Quadlet
`/etc/containers/systemd/windmill-worker.container` (systemd unit
`windmill-worker.service`). The Windmill server is the App Platform app
`fundermaps-windmill-prod` (`MODE=server`); this droplet is the only worker.

The image is built **on the droplet** from this directory — no registry. The
repo is public but its GHCR packages are private, and the droplet has no
registry login; building locally keeps it that way.

## Build and deploy

On the droplet, with `<sha>` the commit to deploy and `<version>` the server's
Windmill version (`curl https://windmill.fundermaps.com/api/version`):

```sh
mkdir -p /tmp/wm-build && cd /tmp/wm-build
curl -fsSLO https://raw.githubusercontent.com/Laixer/FunderMapsWorker/<sha>/windmill-worker/Containerfile
sudo podman build --build-arg WINDMILL_VERSION=<version> \
  -t localhost/fundermaps-windmill-worker:<version> -f Containerfile .
```

Then in the Quadlet file:

```ini
Image=localhost/fundermaps-windmill-worker:<version>
AutoUpdate=local
```

and `sudo systemctl daemon-reload && sudo systemctl restart windmill-worker`.
Restart outside the `:03` hourly `ingest_pending` run and the model-refresh
flow (12:30 and 21:00 Europe/Amsterdam, ~50 min each); a restart kills the
jobs it is running.

`AutoUpdate=local`: there is no registry to poll; the nightly
`podman-auto-update` only restarts the worker when the local image was rebuilt.

## Windmill upgrades

Server and worker move together: bump the App Platform image tag of
`fundermaps-windmill-prod`, then rebuild this image with the same
`WINDMILL_VERSION` and point the Quadlet at the new tag.

## Rollback

Point `Image=` back at the stock image (`ghcr.io/windmill-labs/windmill:<version>`,
`AutoUpdate=registry`), `daemon-reload`, restart. The previous Quadlet file is
kept next to it as `windmill-worker.container.bak-<date>`.
