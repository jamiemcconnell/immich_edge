#!/bin/bash
# Benchmark: measure auth service round-trip latency directly against Immich.
# Run from the immich-edge directory (alongside .env).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

parse_env() {
  local key=$1 file=$2
  grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-
}

ENV_FILE="$SCRIPT_DIR/.env"
IMMICH_INTERNAL_URL="${IMMICH_INTERNAL_URL:-$(parse_env IMMICH_INTERNAL_URL "$ENV_FILE")}"
IMMICH="${IMMICH_INTERNAL_URL:?IMMICH_INTERNAL_URL not set (set in .env or export it)}"

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────

COOKIE="${BENCHMARK_COOKIE:-}"   # set BENCHMARK_COOKIE in env or replace "" here

# ─────────────────────────────────────────────────────────────────

if [[ -z "$COOKIE" ]]; then
  echo "ERROR: set BENCHMARK_COOKIE=immich_access_token=<token> in your shell or .env"
  exit 1
fi

run_test() {
  local url=$1
  local label=$2
  local method=${3:-GET}

  echo ""
  echo "=============================================="
  echo "   $label"
  echo "   $url"
  echo "=============================================="
  for _ in {1..10}; do
    curl -s -o /dev/null \
      -H "Cookie: $COOKIE" \
      -H "Content-Type: application/json" \
      -X "$method" \
      -w "    total=%{time_total}s  connect=%{time_connect}s  ttfb=%{time_starttransfer}s\n" \
      "$url"
  done
}

run_test "$IMMICH/api/users/me"          "GET /api/users/me (session auth)"     GET
run_test "$IMMICH/api/auth/validateToken" "POST /api/auth/validateToken"         POST

echo ""
echo "=============================================="
echo "   DONE"
echo "=============================================="
