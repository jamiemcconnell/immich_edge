#!/bin/sh
set -e

SOURCE="${RSYNC_SOURCE:?RSYNC_SOURCE is required}"
DEST="${CACHE_DIR:-/var/cache/immich-edge}"

# ─── helpers ──────────────────────────────────────────────────────────────────

parse_size_bytes() {
  local val num unit
  val=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  num=$(echo "$val" | sed 's/[^0-9]//g')
  unit=$(echo "$val" | sed 's/[0-9]//g')
  case "$unit" in
    g|gb) echo $((num * 1073741824)) ;;
    m|mb) echo $((num * 1048576)) ;;
    k|kb) echo $((num * 1024)) ;;
    *)    echo "$num" ;;
  esac
}

dir_bytes() { du -sb "$1" 2>/dev/null | cut -f1; }

# Delete oldest files (by mtime) until dir is under limit_bytes.
evict_to_limit() {
  local limit_bytes="$1" dir="$2"
  local used need_free freed=0 tmpfile size path

  used=$(dir_bytes "$dir")
  [ "$used" -le "$limit_bytes" ] && return 0

  need_free=$(( used - limit_bytes ))
  echo "immich-edge sync: cache $(( used / 1048576 ))MB > limit $(( limit_bytes / 1048576 ))MB — freeing $(( need_free / 1048576 ))MB"

  tmpfile=$(mktemp)
  find "$dir" -type f -exec stat -c "%Y %s %n" {} + 2>/dev/null \
    | sort -n > "$tmpfile"

  while IFS= read -r line; do
    [ "$freed" -ge "$need_free" ] && break
    size=$(echo "$line" | awk '{print $2}')
    path=$(echo "$line" | cut -d' ' -f3-)
    rm -f "$path"
    freed=$(( freed + size ))
    echo "  evicted $(( size / 1024 ))KB: $(basename "$path")"
  done < "$tmpfile"
  rm -f "$tmpfile"

  find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  echo "immich-edge sync: cache after eviction: $(( $(dir_bytes "$dir") / 1048576 ))MB / $(( limit_bytes / 1048576 ))MB"
}

rsync_base() {
  if [ -n "${RSYNC_FLAGS:-}" ]; then
    # shellcheck disable=SC2086
    rsync $RSYNC_FLAGS "$@"
  else
    rsync -a --delete --stats --human-readable --timeout=30 --contimeout=10 "$@"
  fi
}

# ─── sync ─────────────────────────────────────────────────────────────────────

sync_path() {
  local sub="$1"
  local src="${SOURCE%/}/${sub}/"
  local dst="${DEST}/${sub}/"
  mkdir -p "$dst"
  echo "immich-edge sync: starting rsync for ${sub} at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "immich-edge sync: source=${src} dest=${dst}"
  rsync_base "$src" "$dst"
  echo "immich-edge sync: completed rsync for ${sub} at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

if [ -n "${CACHE_MAX_SIZE:-}" ]; then
  limit=$(parse_size_bytes "$CACHE_MAX_SIZE")
  # Pre-sync: evict oldest first to make room for incoming new files
  evict_to_limit "$limit" "$DEST"
fi

sync_path "${IMMICH_THUMBS_PATH:-thumbs}"
sync_path "${IMMICH_ENCODED_PATH:-encoded-video}"
sync_path "${IMMICH_PROFILE_PATH:-profile}"

if [ -n "${CACHE_MAX_SIZE:-}" ]; then
  # Post-sync: new files may have pushed us over limit
  evict_to_limit "$limit" "$DEST"
fi

echo "immich-edge sync: seed complete"
