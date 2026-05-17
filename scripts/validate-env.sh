#!/bin/sh
# Validate required environment variables and preconditions before startup.
set -e

ERRORS=0

require_var() {
  local name="$1"
  local val
  val=$(eval echo "\$$name")
  if [ -z "$val" ]; then
    echo "ERROR: $name is required but not set" >&2
    ERRORS=$((ERRORS + 1))
  fi
}

require_var IMMICH_INTERNAL_URL
require_var EDGE_DOMAIN
require_var SSL_EMAIL

# Validate CACHE_MODE
CACHE_MODE="${CACHE_MODE:-proxy}"
if [ "$CACHE_MODE" != "proxy" ] && [ "$CACHE_MODE" != "static" ]; then
  echo "ERROR: CACHE_MODE must be 'proxy' or 'static', got: $CACHE_MODE" >&2
  ERRORS=$((ERRORS + 1))
fi

# Static mode extra requirements
if [ "$CACHE_MODE" = "static" ]; then
  require_var RCLONE_REMOTE
  require_var RCLONE_IMMICH_PATH

  RCLONE_CONFIG="${RCLONE_CONFIG:-/etc/immich-edge/rclone.conf}"
  if [ ! -f "$RCLONE_CONFIG" ]; then
    echo "ERROR: rclone config not found at $RCLONE_CONFIG" >&2
    ERRORS=$((ERRORS + 1))
  fi
fi

# Reachability check for IMMICH_INTERNAL_URL
if command -v wget >/dev/null 2>&1; then
  if ! wget -q --timeout=5 --spider "${IMMICH_INTERNAL_URL}/api/server/ping" 2>/dev/null; then
    echo "WARNING: IMMICH_INTERNAL_URL (${IMMICH_INTERNAL_URL}) does not appear reachable" >&2
    echo "         Ensure the VPN/tunnel is up and the URL is correct." >&2
  else
    echo "OK: Immich reachable at ${IMMICH_INTERNAL_URL}"
  fi
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "Aborting: $ERRORS configuration error(s) found." >&2
  exit 1
fi

echo "validate-env: all checks passed"
