#!/usr/bin/env bash
# workload.sh — Gatling load script for the greener-spring-boot Maven plugin.
# Invoked by the plugin during warmup and measurement windows.
#
# Environment variables injected by the plugin:
#   APP_URL  — base URL of the running Spring Boot app (e.g. http://localhost:8080)
#   RPS      — target requests per second (plugin config: requestsPerSecond)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APP_URL="${APP_URL:-http://localhost:8080}"
RPS="${RPS:-50}"

# Resolve Gatling binary
GATLING_CMD=""
# 1. wrapper created by install-gatling.sh
for _g in "$HOME/.local/bin/gatling.sh" "$HOME/.local/bin/gatling"; do
  [ -x "$_g" ] && GATLING_CMD="$_g" && break
done
# 2. search GATLING_HOME or default install dir (handles non-standard layouts)
if [ -z "$GATLING_CMD" ]; then
  for _gdir in "${GATLING_HOME:-}" "$HOME/.local/gatling"; do
    [ -z "$_gdir" ] && continue
    _found=$(find "$_gdir" -type f \( -name "gatling.sh" -o -name "gatling" \) -not -name "*.bat" 2>/dev/null | head -1)
    if [ -n "$_found" ] && [ -x "$_found" ]; then GATLING_CMD="$_found"; break; fi
  done
fi

if [ -z "$GATLING_CMD" ]; then
  echo "ERROR: Gatling not found. Run: $SCRIPT_DIR/../install-gatling.sh" >&2
  exit 1
fi

# Use RPS as the concurrent user count (close enough for energy measurement).
USERS="$RPS"

exec env MAVEN_OPTS="--enable-native-access=ALL-UNNAMED" \
       JAVA_OPTS="-DbaseUrl=$APP_URL -Dusers=$USERS -DrampSeconds=5 -DdurationSeconds=60" \
  "$GATLING_CMD" \
  -sf "$SCRIPT_DIR/../loadtest" \
  -s PetclinicSimulation \
  -rf /tmp/gatling-results \
  -nr
