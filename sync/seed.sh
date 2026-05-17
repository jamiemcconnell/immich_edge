#!/bin/sh
set -e

REMOTE="${RCLONE_REMOTE:?RCLONE_REMOTE is required}"
BASE="${RCLONE_IMMICH_PATH:?RCLONE_IMMICH_PATH is required}"
DEST="${CACHE_DIR:-/var/cache/immich-edge}"
TRANSFERS="${RCLONE_TRANSFERS:-8}"

sync_path() {
  local src="$1"
  local dst="$2"
  echo "syncing $src -> $dst"
  rclone sync \
    --config /etc/immich-edge/rclone.conf \
    --transfers "$TRANSFERS" \
    --checksum \
    --progress \
    "${REMOTE}:${BASE}/${src}" \
    "${dst}"
}

sync_path "${IMMICH_THUMBS_PATH:-thumbs}"        "${DEST}/${IMMICH_THUMBS_PATH:-thumbs}"
sync_path "${IMMICH_ENCODED_PATH:-encoded-video}" "${DEST}/${IMMICH_ENCODED_PATH:-encoded-video}"
sync_path "${IMMICH_PROFILE_PATH:-profile}"       "${DEST}/${IMMICH_PROFILE_PATH:-profile}"

echo "seed complete"
