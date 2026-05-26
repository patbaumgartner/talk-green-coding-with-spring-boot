#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Demo 01 — JoularCore: system-wide CPU power monitoring
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT IT DOES
#   1. Starts Spring PetClinic on a random port
#   2. Resolves the real OS process ID via jps — on Windows/Git Bash, $! is a
#      MSYS pseudo-PID and JoularCore needs the native Windows PID
#   3. Attaches JoularCore in --pid mode: samples CPU power once per second
#      and writes a timestamped CSV with per-process power readings (Watts)
#   4. Runs a 60-second Gatling load test (10 concurrent users)
#   5. Stops both processes and prints the captured power trace
#
# OUTPUT
#   joularcore-YYYYMMDD-HHMMSS.csv  (in this demo directory)
#   Columns: Timestamp | Total Power (W) | CPU Power (W) | GPU Power (W)
#            | CPU Usage (%) | Process Power (W)
#
# PREREQUISITES
#   - joularcore ≥ 0.1.0  →  install-joularcore.sh  /  install-joularcore.ps1
#   - Gatling ≥ 3.13      →  install-gatling.sh
#   - Java 17+ with jps   →  java -version
#   - Spring PetClinic    →  install-spring-petclinic.sh
#
# Linux RAPL (run once):  sudo chmod -R a+r /sys/class/powercap/intel-rapl
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$DEMO_DIR/console.log") 2>&1
PETCLINIC_DIR="$DEMO_DIR/../spring-petclinic"
RUN_TS=$(date +%Y%m%d-%H%M%S)
JOULARCORE_CSV="$DEMO_DIR/joularcore-$RUN_TS.csv"
PETCLINIC_LOG="/tmp/petclinic-$$.log"

# Process IDs — initialized to empty so the EXIT trap is always safe to call
TAIL_PID=""
PETCLINIC_SHELL_PID=""
PETCLINIC_PID=""
JOULARCORE_PID=""

# ─── Helpers ─────────────────────────────────────────────────────────────────

log() { echo ""; echo "==> $*"; }

die() {
  echo "" >&2
  echo "ERROR: $1" >&2
  shift
  for _hint in "$@"; do echo "  $_hint" >&2; done
  exit 1
}

# Populates GATLING_CMD with the first usable Gatling binary found.
# Tries the wrapper installed by install-gatling.sh first, then searches
# GATLING_HOME and ~/.local/gatling for any gatling[.sh] executable.
find_gatling() {
  GATLING_CMD=""
  for _g in "$HOME/.local/bin/gatling.sh" "$HOME/.local/bin/gatling"; do
    [ -x "$_g" ] && { GATLING_CMD="$_g"; return 0; }
  done
  for _gdir in "${GATLING_HOME:-}" "$HOME/.local/gatling"; do
    [ -z "$_gdir" ] && continue
    local _found
    _found=$(find "$_gdir" -type f \( -name "gatling.sh" -o -name "gatling" \) \
             -not -name "*.bat" 2>/dev/null | head -1)
    [ -n "$_found" ] && [ -x "$_found" ] && { GATLING_CMD="$_found"; return 0; }
  done
  return 1
}

# Kills every background process started by this script.
# Runs automatically on EXIT so orphaned processes are cleaned up even when
# the script aborts early (set -e, Ctrl-C, preflight failure, etc.).
cleanup() {
  [ -n "$TAIL_PID"            ] && kill "$TAIL_PID"            2>/dev/null || true
  [ -n "$JOULARCORE_PID"      ] && kill "$JOULARCORE_PID"      2>/dev/null || true
  [ -n "$PETCLINIC_PID"       ] && kill "$PETCLINIC_PID"       2>/dev/null || true
  [ -n "$PETCLINIC_SHELL_PID" ] && kill "$PETCLINIC_SHELL_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ─── Preflight ───────────────────────────────────────────────────────────────

[ -f "$PETCLINIC_DIR/mvnw" ] \
  || die "spring-petclinic submodule not initialized." \
         "Run:  bash install-spring-petclinic.sh" \
         "  or: git submodule update --init demos/spring-petclinic"

command -v joularcore >/dev/null 2>&1 \
  || die "joularcore not found in PATH." \
         "Linux:   bash install-joularcore.sh" \
         "Windows: run install-joularcore.ps1 as Administrator, then reopen the terminal"

GATLING_CMD=""
find_gatling \
  || die "Gatling not found." \
         "Run: bash install-gatling.sh"

# ─── Clean ───────────────────────────────────────────────────────────────────

log "Cleaning previous run artifacts..."
rm -f "$DEMO_DIR"/joularcore-*.csv

# ─── Build ───────────────────────────────────────────────────────────────────

log "Building spring-petclinic (skipped if JAR already exists)..."
cd "$PETCLINIC_DIR"
JAR=$(ls target/spring-petclinic-*.jar 2>/dev/null | head -1 || true)
if [ -z "$JAR" ]; then
  bash ./mvnw -ntp package -DskipTests
  JAR=$(ls target/spring-petclinic-*.jar | head -1)
else
  log "Reusing existing JAR: $(basename "$JAR")"
fi
log "JAR: $JAR"

# ─── Start application ───────────────────────────────────────────────────────

log "Starting Spring PetClinic on a random port..."
> "$PETCLINIC_LOG"
java -jar "$JAR" --server.port=0 \
  > "$PETCLINIC_LOG" 2>&1 &
PETCLINIC_SHELL_PID=$!

# Stream startup logs until Tomcat reports its port, then stop the tail
tail -f "$PETCLINIC_LOG" &
TAIL_PID=$!
until grep -qE 'Tomcat started on port' "$PETCLINIC_LOG" 2>/dev/null; do sleep 1; done
kill $TAIL_PID 2>/dev/null; wait $TAIL_PID 2>/dev/null || true

PORT=$(grep -oE 'Tomcat started on port[^0-9]*[0-9]+' "$PETCLINIC_LOG" \
       | grep -oE '[0-9]+' | head -1)
log "PetClinic listening on port $PORT"

echo -n "    Waiting for health check"
until curl -sf "http://localhost:$PORT/actuator/health" >/dev/null 2>&1; do
  sleep 1; echo -n "."
done
echo " ready"

# On Windows/Git Bash, $! holds the MSYS pseudo-PID, not the Windows PID.
# JoularCore requires the native OS PID.  Resolve it via jps (ships with the
# JDK) and fall back to $! only when jps is unavailable or returns nothing.
PETCLINIC_PID=$(jps -l 2>/dev/null \
  | grep -i "spring-petclinic" | awk '{print $1}' | head -1)
if [ -z "$PETCLINIC_PID" ]; then
  PETCLINIC_PID=$PETCLINIC_SHELL_PID
  log "WARNING: jps lookup failed — falling back to shell PID $PETCLINIC_PID"
fi
log "PetClinic native PID: $PETCLINIC_PID"

# ─── Start power monitor ─────────────────────────────────────────────────────

log "Starting JoularCore (monitoring PID $PETCLINIC_PID)..."
# --pid                          attach to this specific process
# --file                         write per-second power samples to CSV
# --calibrate-cpu-idle-baseline  subtract idle power → shows net application cost
# --silent                       suppress per-second console output
joularcore --pid "$PETCLINIC_PID" \
           --file "$JOULARCORE_CSV" \
           --calibrate-cpu-idle-baseline \
           --silent &
JOULARCORE_PID=$!
log "JoularCore PID: $JOULARCORE_PID (calibrating idle baseline for 6 s...)"
sleep 6

# ─── Load test ───────────────────────────────────────────────────────────────

log "Running Gatling load test (60 s, 10 concurrent users)..."
MAVEN_OPTS="--enable-native-access=ALL-UNNAMED" \
JAVA_OPTS="-DbaseUrl=http://localhost:$PORT -Dusers=10 -DrampSeconds=5 -DdurationSeconds=60" \
  "$GATLING_CMD" \
    -sf "$DEMO_DIR/../loadtest" \
    -s PetclinicSimulation \
    -rf /tmp/gatling-results \
    -nr 2>&1 \
  | grep -v '^WARNING:' \
  | grep -E '(request|users|error|mean|p99|ERROR|WARN|^_)' \
  || true
log "Load test complete."

# ─── Shutdown ────────────────────────────────────────────────────────────────

log "Stopping JoularCore and PetClinic..."
# JoularCore writes its CSV live (not in a shutdown hook), so a plain kill is
# safe here — no data is lost regardless of how the process exits.
kill $JOULARCORE_PID 2>/dev/null || true
kill $PETCLINIC_PID  2>/dev/null || true

# ─── Results ─────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " JoularCore power trace — run $RUN_TS"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
cat "$JOULARCORE_CSV" | column -t -s ','
