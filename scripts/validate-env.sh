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
require_var TRUSTED_PROXIES

# Validate CACHE_MODE
CACHE_MODE="${CACHE_MODE:-proxy}"
if [ "$CACHE_MODE" != "proxy" ] && [ "$CACHE_MODE" != "static" ]; then
  echo "ERROR: CACHE_MODE must be 'proxy' or 'static', got: $CACHE_MODE" >&2
  ERRORS=$((ERRORS + 1))
fi

RATE_LIMIT="${RATE_LIMIT:-20}"
if ! echo "$RATE_LIMIT" | grep -Eq '^[0-9]+$'; then
  echo "ERROR: RATE_LIMIT must be a positive integer, got: $RATE_LIMIT" >&2
  ERRORS=$((ERRORS + 1))
fi

# Static mode extra requirements
if [ "$CACHE_MODE" = "static" ]; then
  require_var RSYNC_SOURCE

  # Validate trusted proxies values (CIDRs/IPs, comma-separated)
  FOUND_PROXY=0
  for proxy in $(echo "$TRUSTED_PROXIES" | tr ',' ' '); do
    FOUND_PROXY=1
    if ! echo "$proxy" | grep -Eq '^[0-9a-fA-F:.]+(/[0-9]{1,3})?$'; then
      echo "ERROR: TRUSTED_PROXIES entry is invalid: $proxy" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done
  if [ "$FOUND_PROXY" -eq 0 ]; then
    echo "ERROR: TRUSTED_PROXIES must include at least one CIDR/IP entry" >&2
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
