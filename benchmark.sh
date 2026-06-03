#!/bin/bash
# Benchmark: compare latency via immich-edge vs direct home server.
# Run from the immich-edge directory (alongside .env).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

parse_env() {
  local key=$1 file=$2
  grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-
}

ENV_FILE="$SCRIPT_DIR/.env"
EDGE_URL="${EDGE_URL:-$(parse_env EDGE_URL "$ENV_FILE")}"
EDGE_DOMAIN="${EDGE_DOMAIN:-$(parse_env EDGE_DOMAIN "$ENV_FILE")}"
IMMICH_INTERNAL_URL="${IMMICH_INTERNAL_URL:-$(parse_env IMMICH_INTERNAL_URL "$ENV_FILE")}"

if [[ -z "$EDGE_URL" ]]; then
  EDGE_URL="https://${EDGE_DOMAIN:?EDGE_URL not set (set EDGE_URL or EDGE_DOMAIN in .env/export)}"
fi
HOME_URL="${IMMICH_INTERNAL_URL:?IMMICH_INTERNAL_URL not set (set in .env or export it)}"

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION — paste your session cookie and a few asset paths
# Get asset paths from the browser: open DevTools → Network → filter
# for "thumbnail" → copy the path of any thumbnail request.
# ─────────────────────────────────────────────────────────────────

COOKIE="${BENCHMARK_COOKIE:-}"   # set BENCHMARK_COOKIE in env or replace "" here

# Asset paths (no domain) — add as many as you like
asset_paths=(
  # "/api/assets/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/thumbnail?size=thumbnail"
  # "/api/assets/yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy/thumbnail?size=preview"
)

# ─────────────────────────────────────────────────────────────────

if [[ -z "$COOKIE" ]]; then
  echo "ERROR: set BENCHMARK_COOKIE=immich_access_token=<token> in your shell or .env"
  exit 1
fi

if [[ ${#asset_paths[@]} -eq 0 ]]; then
  echo "ERROR: add at least one asset path to the asset_paths array in this script"
  exit 1
fi

run_urls() {
  local base=$1
  local label=$2
  echo ""
  echo "=============================================="
  echo "   $label"
  echo "   $base"
  echo "=============================================="
  for path in "${asset_paths[@]}"; do
    echo ""
    echo "  $path"
    echo "  ──────────────────────────────────────────"
    for _ in {1..10}; do
      curl -s -o /dev/null \
        -H "Cookie: $COOKIE" \
        -w "    total=%{time_total}s  connect=%{time_connect}s  ttfb=%{time_starttransfer}s\n" \
        "${base}${path}"
    done
  done
}

run_urls "$EDGE_URL"  "VIA immich-edge (VPS)"
run_urls "$HOME_URL"  "DIRECT → home server (bypass VPS)"

echo ""
echo "=============================================="
echo "   DONE — compare VPS vs Direct timings"
echo "=============================================="
