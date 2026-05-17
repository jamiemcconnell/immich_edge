#!/bin/sh
# Healthcheck for the auth service container
AUTH_PORT="${AUTH_PORT:-8088}"
wget -q -O- "http://localhost:${AUTH_PORT}/health" || exit 1
