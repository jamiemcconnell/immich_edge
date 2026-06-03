#!/bin/sh
set -e

INTERVAL="${RSYNC_SYNC_INTERVAL:-60}"

echo "immich-edge sync: running initial seed"
/seed.sh

if [ "$INTERVAL" = "0" ]; then
  echo "immich-edge sync: RSYNC_SYNC_INTERVAL=0, one-time seed only, exiting"
  exit 0
fi

echo "immich-edge sync: continuous sync every ${INTERVAL}s"
while true; do
  sleep "$INTERVAL"
  echo "immich-edge sync: running sync at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if /seed.sh; then
    :
  else
    rc=$?
    echo "immich-edge sync: sync failed (exit $rc), will retry next interval"
  fi
done
