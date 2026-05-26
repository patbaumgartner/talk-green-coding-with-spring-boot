#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Demo 02 — JoularJX: per-method energy profiling
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT IT DOES
#   1. Downloads the JoularJX Java agent JAR if not already present
#   2. Builds a temporary config that injects the joularcore binary path —
#      on Windows/Git Bash the JVM needs a native Windows path (C:/...) which
#      differs from the POSIX path (/c/...) returned by `command -v`
#   3. Starts Spring PetClinic with the JoularJX agent attached
#      → JoularJX automatically spawns JoularCore as a subprocess to sample
#        CPU power once per second (stdout mode: joularcore -c cpu -i)
#      → Per-cycle energy per method is written live to app/runtime/methods/
#   4. Runs a 60-second Gatling load test (10 concurrent users)
#   5. Shuts down PetClinic via the Spring Boot actuator for a graceful JVM
#      exit, which triggers JoularJX's shutdown hook to write the aggregated
#      per-method energy totals to app/total/methods/
#   6. Prints the top 10 methods by total energy consumed
#
# OUTPUT
#   joularjx-result/<pid>-<timestamp>/
#     app/total/methods/    — aggregated per-method energy (J)  [shutdown hook]
#     app/runtime/methods/  — per-cycle samples (J)             [written live]
#
# PREREQUISITES
#   - joularcore ≥ 0.1.0  →  install-joularcore.sh  /  install-joularcore.ps1
#   - Gatling ≥ 3.13      →  install-gatling.sh
#   - Java 17+            →  java -version
#   - Spring PetClinic    →  install-spring-petclinic.sh
#
# Linux RAPL (run once):  sudo chmod -R a+r /sys/class/powercap/intel-rapl
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$DEMO_DIR/console.log") 2>&1
PETCLINIC_DIR="$DEMO_DIR/../spring-petclinic"
AGENT="$DEMO_DIR/joularjx-3.1.0.jar"
PETCLINIC_LOG="/tmp/petclinic-$$.log"

# Process IDs and temp files — initialized to empty so the EXIT trap is always safe to call
TAIL_PID=""
PETCLINIC_PID=""
RUNTIME_CONFIG=""

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

# Kills every background process started by this script and removes temp files.
# Runs automatically on EXIT so orphaned processes are cleaned up even when
# the script aborts early (set -e, Ctrl-C, preflight failure, etc.).
cleanup() {
  [ -n "$TAIL_PID"      ] && kill "$TAIL_PID"      2>/dev/null || true
  [ -n "$PETCLINIC_PID" ] && kill "$PETCLINIC_PID" 2>/dev/null || true
  [ -n "$RUNTIME_CONFIG" ] && rm -f "$RUNTIME_CONFIG" 2>/dev/null || true
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

# Download the JoularJX agent JAR if not already present
if [ -f "$AGENT" ]; then
  log "JoularJX agent already present: $(basename "$AGENT")"
else
  log "Downloading JoularJX agent (joularjx-3.1.0.jar)..."
  curl -fLo "$AGENT" \
    https://github.com/joular/joularjx/releases/download/3.1.0/joularjx-3.1.0.jar
fi

# ─── Clean ───────────────────────────────────────────────────────────────────

log "Cleaning previous run artifacts..."
rm -rf "$DEMO_DIR/joularjx-result"

# ─── Build ───────────────────────────────────────────────────────────────────

log "Building spring-petclinic (skipped if JAR already exists)..."
cd "$PETCLINIC_DIR"
JAR=$(ls "$PETCLINIC_DIR"/target/spring-petclinic-*.jar 2>/dev/null | head -1 || true)
if [ -z "$JAR" ]; then
  bash ./mvnw -ntp package -DskipTests
  JAR=$(ls "$PETCLINIC_DIR"/target/spring-petclinic-*.jar | head -1)
else
  log "Reusing existing JAR: $(basename "$JAR")"
fi
log "JAR: $JAR"

# ─── Runtime config ──────────────────────────────────────────────────────────

# JoularJX reads joular-core-path from its properties file to locate the
# JoularCore binary it spawns as a subprocess.  On Windows/Git Bash,
# `command -v` returns a POSIX path (/c/Users/...); the JVM (which runs
# natively on Windows) cannot resolve that.  cygpath -m converts it to a
# mixed Windows path (C:/Users/...) that both bash and the JVM can use.
JOULARCORE_BIN=$(command -v joularcore)
if command -v cygpath >/dev/null 2>&1; then
  JOULARCORE_BIN=$(cygpath -m "$JOULARCORE_BIN")
fi
log "JoularCore binary: $JOULARCORE_BIN"

# Write a temp config extending config.properties with the resolved binary path.
# JoularJX will start JoularCore automatically as a subprocess (stdout mode).
RUNTIME_CONFIG=$(mktemp --suffix=.properties)
cat "$DEMO_DIR/config.properties" > "$RUNTIME_CONFIG"
printf '\njoular-core-path=%s\n' "$JOULARCORE_BIN" >> "$RUNTIME_CONFIG"
log "Runtime config written (joular-core-path=$JOULARCORE_BIN)"

# ─── Start application ───────────────────────────────────────────────────────

log "Starting Spring PetClinic with JoularJX agent..."
cd "$DEMO_DIR"
> "$PETCLINIC_LOG"
java -javaagent:"$AGENT" \
     -Djoularjx.config="$RUNTIME_CONFIG" \
     -Dmanagement.endpoint.shutdown.enabled=true \
     -jar "$JAR" --server.port=0 \
  > "$PETCLINIC_LOG" 2>&1 &
PETCLINIC_PID=$!
log "PetClinic PID: $PETCLINIC_PID"

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

log "Shutting down PetClinic gracefully (JoularJX writes total/methods on JVM exit)..."
# The actuator endpoint triggers a graceful JVM exit which runs shutdown hooks.
# JoularJX registers a hook to flush aggregated per-method energy totals to
# app/total/methods/ — without this, only the live per-cycle data is available.
#
# Fallback: kill -TERM.  On Windows/Git Bash this calls TerminateProcess(),
# which is immediate and skips all shutdown hooks.
curl -sf -X POST "http://localhost:$PORT/actuator/shutdown" >/dev/null 2>&1 \
  || kill -TERM $PETCLINIC_PID

# Poll until the process exits (wait can hang on Windows/MSYS when the
# process was already reaped by the OS)
_t=30
while [ $_t -gt 0 ] && kill -0 $PETCLINIC_PID 2>/dev/null; do
  sleep 1; _t=$((_t - 1))
done

# ─── Results ─────────────────────────────────────────────────────────────────

LATEST_RUN=$(find "$DEMO_DIR/joularjx-result" -mindepth 1 -maxdepth 1 -type d \
             2>/dev/null | sort | tail -1)
TOTAL_DIR="$LATEST_RUN/app/total/methods"
RUNTIME_DIR="$LATEST_RUN/app/runtime/methods"

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " JoularJX — top 10 methods by total energy (J)"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

if [ -d "$TOTAL_DIR" ] && ls "$TOTAL_DIR"/*.csv >/dev/null 2>&1; then
  # Preferred path: single aggregated file written by the JVM shutdown hook
  TOTAL_CSV=$(ls -t "$TOTAL_DIR"/*.csv | head -1)
  { printf 'method,energy_J\n'; sort -t',' -k2 -rn "$TOTAL_CSV" | head -10; } \
    | column -t -s ','
elif [ -d "$RUNTIME_DIR" ]; then
  # Fallback: aggregate the per-cycle runtime samples.
  # Less accurate but available even when the JVM was killed before hooks ran.
  echo "(note: using per-cycle runtime data — shutdown hook did not run)"
  echo ""
  find "$RUNTIME_DIR" -name "*-filtered-methods-power.csv" \
    | xargs cat 2>/dev/null \
    | awk -F',' '{sum[$1]+=$2} END{for(m in sum) print m","sum[m]}' \
    | sort -t',' -k2 -rn | head -10 \
    | { printf 'method,energy_J\n'; cat; } \
    | column -t -s ','
else
  echo "(no results found — check joularjx-result/ for run output)"
fi
