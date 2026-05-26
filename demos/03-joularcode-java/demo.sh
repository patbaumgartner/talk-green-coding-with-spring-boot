#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Demo 03 — JoularCode Java: call-branch energy profiling
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT IT DOES
#   1. Downloads the JoularCode Java agent JAR if not already present
#   2. Starts JoularCore in ring-buffer mode as a standalone power source:
#        joularcore --app java --ringbuffer
#      JoularCore writes per-second CPU power samples to a shared-memory ring
#      buffer that the agent reads concurrently (no subprocess spawning)
#   3. Builds a temporary properties file from joularcodejava.properties;
#      on Windows the ring-buffer path is overridden to Local\JoularCoreRing
#      (the Linux default /dev/shm/joularcorering does not exist on Windows)
#   4. Starts Spring PetClinic with the JoularCode Java agent attached
#   5. Runs a 60-second Gatling load test (10 concurrent users)
#   6. Shuts down PetClinic via the Spring Boot actuator, then stops JoularCore
#   7. Archives the results CSV and prints the top 10 call branches by energy
#
# OUTPUT
#   joular-code-java-results/methods-power-app.csv         — filtered branches (petclinic)
#   joular-code-java-results/methods-power-all.csv         — all branches (unfiltered)
#   joular-code-java-results/methods-power-app-YYYYMMDD-HHMMSS.csv  — archived copy
#   CSV columns: timestamp | branch | power_watts | energy_joules | interval_seconds
#
# PREREQUISITES
#   - joularcore ≥ 0.1.0  →  install-joularcore.sh  /  install-joularcore.ps1
#   - Gatling ≥ 3.13      →  install-gatling.sh
#   - Java 21+            →  java -version
#   - Spring PetClinic    →  install-spring-petclinic.sh
#
# Linux RAPL (run once):  sudo chmod -R a+r /sys/class/powercap/intel-rapl
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$DEMO_DIR/console.log") 2>&1
PETCLINIC_DIR="$DEMO_DIR/../spring-petclinic"
AGENT="$DEMO_DIR/joularcodejava-0.0.1-alpha-4.jar"
RUN_TS=$(date +%Y%m%d-%H%M%S)
PETCLINIC_LOG="/tmp/petclinic-$$.log"

# Process IDs and temp files — initialized to empty so the EXIT trap is always safe to call
TAIL_PID=""
PETCLINIC_PID=""
JOULARCORE_PID=""
RUNTIME_PROPS=""

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
  [ -n "$TAIL_PID"       ] && kill "$TAIL_PID"       2>/dev/null || true
  [ -n "$JOULARCORE_PID" ] && kill "$JOULARCORE_PID" 2>/dev/null || true
  [ -n "$PETCLINIC_PID"  ] && kill "$PETCLINIC_PID"  2>/dev/null || true
  [ -n "$RUNTIME_PROPS"  ] && rm -f "$RUNTIME_PROPS"  2>/dev/null || true
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

# Download the JoularCode Java agent JAR if not already present
if [ -f "$AGENT" ]; then
  log "JoularCode Java agent already present: $(basename "$AGENT")"
else
  log "Downloading JoularCode Java agent (joularcodejava-0.0.1-alpha-4.jar)..."
  curl -fLo "$AGENT" \
    https://github.com/joular/joularcode-java/releases/download/0.0.1-alpha-4/joularcodejava-0.0.1.jar
fi

# ─── Clean ───────────────────────────────────────────────────────────────────

log "Cleaning previous run artifacts..."
rm -rf "$DEMO_DIR/joular-code-java-results"

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

# ─── Runtime properties ──────────────────────────────────────────────────────

# Build a temp properties file from joularcodejava.properties.  On Windows,
# append an override for joular-core-ringbuffer-path because the Linux default
# (/dev/shm/joularcorering) does not exist on Windows; the Windows equivalent
# is the named file-mapping Local\JoularCoreRing.
#
# Java Properties escaping: Properties.load() treats \ as an escape character.
# To produce Local\JoularCoreRing at runtime the file must contain
# Local\\JoularCoreRing.  printf '\\\\' in a single-quoted string writes two
# literal backslashes to the file; Java then reads \\ → \.
RUNTIME_PROPS=$(mktemp --suffix=.properties)
cat "$DEMO_DIR/joularcodejava.properties" > "$RUNTIME_PROPS"
if command -v cygpath >/dev/null 2>&1; then
  printf '\njoular-core-ringbuffer-path=Local\\\\JoularCoreRing\n' >> "$RUNTIME_PROPS"
  log "Ring-buffer path overridden for Windows: Local\\JoularCoreRing"
fi

# ─── Start power source ──────────────────────────────────────────────────────

log "Starting JoularCore in ring-buffer mode (power source for the agent)..."
# --app java                     monitor the java process by name
# --ringbuffer                   write power samples to shared-memory ring buffer
# --calibrate-cpu-idle-baseline  subtract idle power → shows net application cost
# --silent                       suppress per-second console output
joularcore --app java \
           --ringbuffer \
           --calibrate-cpu-idle-baseline \
           --silent &
JOULARCORE_PID=$!
log "JoularCore PID: $JOULARCORE_PID (calibrating idle baseline for 6 s...)"
sleep 6

# ─── Start application ───────────────────────────────────────────────────────

log "Starting Spring PetClinic with JoularCode Java agent..."
cd "$DEMO_DIR"
> "$PETCLINIC_LOG"
java -Djoularcodejava.properties="$RUNTIME_PROPS" \
     -javaagent:"$AGENT" \
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

log "Shutting down PetClinic and JoularCore..."
# Graceful shutdown via actuator so the JVM runs its shutdown hooks.
# Fallback: kill -TERM (on Windows/Git Bash this calls TerminateProcess —
# immediate, skips all shutdown hooks).
curl -sf -X POST "http://localhost:$PORT/actuator/shutdown" >/dev/null 2>&1 \
  || kill -TERM $PETCLINIC_PID

# Poll until the process exits (wait can hang on Windows/MSYS)
_t=30
while [ $_t -gt 0 ] && kill -0 $PETCLINIC_PID 2>/dev/null; do
  sleep 1; _t=$((_t - 1))
done
kill $JOULARCORE_PID 2>/dev/null || true

# ─── Results ─────────────────────────────────────────────────────────────────

APP_CSV="$DEMO_DIR/joular-code-java-results/methods-power-app.csv"

# Archive a timestamped copy so successive runs can be compared later
if [ -f "$APP_CSV" ]; then
  cp "$APP_CSV" "$DEMO_DIR/joular-code-java-results/methods-power-app-$RUN_TS.csv"
fi

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " JoularCode Java — top 10 call branches by cumulative energy (J)"
echo "══════════════════════════════════════════════════════════════════════"
echo ""

if [ -f "$APP_CSV" ]; then
  # Aggregate energy_joules ($4) per branch ($2), sort descending, take top 10
  { printf 'energy_J branch\n'
    awk -F',' 'NR>1{e[$2]+=$4} END{for(b in e) print e[b],b}' "$APP_CSV" \
      | sort -rn | head -10
  } | column -t
else
  echo "(no results found — check joular-code-java-results/ for run output)"
fi
