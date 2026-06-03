#!/bin/sh
set -e

MODE="${CACHE_MODE:-proxy}"
TEMPLATE_DIR="/etc/nginx/templates"
CONF_OUT="/usr/local/openresty/nginx/conf/nginx.conf"

case "$MODE" in
  proxy)  TMPL="$TEMPLATE_DIR/nginx-proxy.conf.template" ;;
  static) TMPL="$TEMPLATE_DIR/nginx-static.conf.template" ;;
  *)
    echo "ERROR: unknown CACHE_MODE '$MODE'. Must be 'proxy' or 'static'." >&2
    exit 1
    ;;
esac

echo "immich-edge: starting nginx in $MODE mode"

# Extract host:port from IMMICH_INTERNAL_URL for the upstream block
# e.g. http://100.74.127.94:2283 -> 100.74.127.94:2283
IMMICH_BACKEND=$(echo "${IMMICH_INTERNAL_URL}" | sed 's|^https\?://||' | sed 's|/.*||')
export IMMICH_BACKEND

TRUSTED_PROXIES="${TRUSTED_PROXIES:-}"
if [ -z "$TRUSTED_PROXIES" ]; then
  echo "ERROR: TRUSTED_PROXIES is required (comma-separated CIDRs/IPs for upstream proxies)" >&2
  exit 1
fi

TRUSTED_PROXIES_NGINX=""
for proxy in $(echo "$TRUSTED_PROXIES" | tr ',' ' '); do
  [ -z "$proxy" ] && continue
  TRUSTED_PROXIES_NGINX="${TRUSTED_PROXIES_NGINX}    set_real_ip_from ${proxy};
"
done
if [ -z "$TRUSTED_PROXIES_NGINX" ]; then
  echo "ERROR: TRUSTED_PROXIES did not contain any valid CIDR/IP entries" >&2
  exit 1
fi
export TRUSTED_PROXIES_NGINX

# Substitute only our env vars; nginx's $var references are left untouched
envsubst '${IMMICH_INTERNAL_URL} ${IMMICH_BACKEND} ${CACHE_MODE} ${CACHE_MAX_SIZE} ${CACHE_TTL} ${CACHE_TTL_404} ${CACHE_DIR} ${CACHE_PATTERN_THUMBS} ${CACHE_PATTERN_VIDEOS} ${AUTH_PORT} ${NGINX_WORKERS} ${IMMICH_THUMBS_PATH} ${IMMICH_ENCODED_PATH} ${IMMICH_PROFILE_PATH} ${RATE_LIMIT} ${TRUSTED_PROXIES_NGINX} ${CACHE_MIN_USES} ${CACHE_BACKGROUND_UPDATE}' \
  < "$TMPL" > "$CONF_OUT"

# Allow nobody (worker processes) to write logs
touch /var/log/nginx/access.log /var/log/nginx/error.log
chmod 666 /var/log/nginx/access.log /var/log/nginx/error.log

exec /usr/local/openresty/bin/openresty -g "daemon off;"
