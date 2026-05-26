#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Demo 05 — greener Maven plugin + JoularCode Java: per-method energy profiling
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT IT DOES
#   1. greener:doctor          — verify environment (RAPL access, JoularCore,
#                                workload script)
#   2. mvn package             — build the Spring PetClinic fat-jar
#   3. greener:measure         — start the app (with JoularCode Java agent
#                                attached), run the workload, record energy;
#                                JoularCore must be running in ring-buffer mode
#                                BEFORE the plugin starts the app so the agent
#                                can open the shared-memory mapping on startup
#   4. greener:update-baseline — promote the latest result to energy-baseline.json
#   5. greener:measure         — second run: regression detection + method-level
#                                energy breakdown for both runs
#
# OUTPUT
#   reports/                                — HTML energy report
#   energy-baseline.json                    — baseline snapshot
#   energy-baseline-trend.json              — rolling trend
#   reports/script/work/joular-code-java-results/
#     methods-power-app.csv                 — per-method energy (petclinic only)
#     methods-power-all.csv                 — per-method energy (unfiltered)
#
# PREREQUISITES
#   - Java 17+ with Maven wrapper   →  demos/spring-petclinic/mvnw
#   - Gatling ≥ 3.13                →  install-gatling.sh
#   - Spring PetClinic submodule    →  install-spring-petclinic.sh
#   - joularcore in PATH            →  install-joularcore.sh / install-joularcore.ps1
#   - JoularCode Java agent JAR     →  demos/03-joularcode-java/
#                                      (downloaded on first run if missing)
#
# Linux RAPL (run once):  sudo chmod -R a+r /sys/class/powercap/intel-rapl
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$DEMO_DIR/console.log") 2>&1
PETCLINIC_DIR="$DEMO_DIR/../spring-petclinic"

# Reuse the Gatling workload from demo 04 — both demos share the same
# loadtest scenario and the workload.sh resolves loadtest/ relative to its
# own directory, so the path to PetclinicSimulation.java is still correct
WORKLOAD="$DEMO_DIR/../04-greener-maven-plugin/workload.sh"

BASELINE="$DEMO_DIR/energy-baseline.json"
REPORT_DIR="$DEMO_DIR/reports"
# JoularCode Java results land inside the plugin's working directory:
#   <reportOutputDir>/script/work/joular-code-java-results/
RESULTS_DIR="$DEMO_DIR/reports/script/work/joular-code-java-results"
RUN_TS=$(date +%Y%m%d-%H%M%S)

# JoularCode Java agent JAR and base properties — kept in demo 03 so a single
# copy is shared across demos; demo.sh downloads the JAR there if missing
AGENT_JAR="$DEMO_DIR/../03-joularcode-java/joularcodejava-0.0.1-alpha-4.jar"
AGENT_PROPS_BASE="$DEMO_DIR/../03-joularcode-java/joularcodejava.properties"

# Temp properties file built at runtime (contains platform-specific overrides)
RUNTIME_PROPS=""

# Maven plugin coordinates — no pom.xml modification needed
GREENER="com.patbaumgartner:greener-spring-boot-maven-plugin:0.2.0-SNAPSHOT"

# ─── Helpers ─────────────────────────────────────────────────────────────────

log()  { echo ""; echo "==> $*"; }

die() {
  echo "" >&2
  echo "ERROR: $1" >&2
  shift
  for _hint in "$@"; do echo "  $_hint" >&2; done
  exit 1
}

step() {
  echo ""
  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo " STEP $1: $2"
  echo "══════════════════════════════════════════════════════════════════════"
}

# Displays the top 10 methods by cumulative energy from the results CSV.
show_method_results() {
  local _csv="$RESULTS_DIR/methods-power-app.csv"

  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo " JoularCode Java — top 10 methods by cumulative energy (J)"
  echo "══════════════════════════════════════════════════════════════════════"
  echo ""

  if [ -f "$_csv" ]; then
    # Archive a timestamped copy so successive runs can be compared
    cp "$_csv" "$RESULTS_DIR/methods-power-app-$RUN_TS.csv"
    # Aggregate energy_joules ($4) per method ($2), sort descending, top 10
    { printf 'energy_J method\n'
      awk -F',' 'NR>1{e[$2]+=$4} END{for(m in e) print e[m],m}' "$_csv" \
        | sort -rn | head -10
    } | column -t
  else
    echo "(no results found — check $RESULTS_DIR/ for run output)"
  fi
}

# Removes the temp properties file on EXIT.
cleanup() {
  [ -n "$RUNTIME_PROPS" ] && rm -f "$RUNTIME_PROPS" 2>/dev/null || true
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

# Download the JoularCode Java agent into the shared demo-03 directory if it
# is not already present (mirrors the download logic in demo 03)
if [ -f "$AGENT_JAR" ]; then
  log "JoularCode Java agent: $(basename "$AGENT_JAR")"
else
  log "Downloading JoularCode Java agent..."
  curl -fLo "$AGENT_JAR" \
    https://github.com/joular/joularcode-java/releases/download/0.0.1-alpha-4/joularcodejava-0.0.1.jar
fi

# Capture git context so commitSha/branch are not null in the baseline JSON
GIT_SHA=$(git -C "$DEMO_DIR" rev-parse --short HEAD 2>/dev/null || echo "")
GIT_BRANCH=$(git -C "$DEMO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Pick a free port — the plugin has no startup-log parser so both appArgs and
# baseUrl must reference the same pre-selected port
APP_PORT=$(python3 -c \
  "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
log "Using port $APP_PORT for Spring PetClinic"

# ─── Runtime properties ──────────────────────────────────────────────────────

# Build a temp copy of joularcodejava.properties with two overrides:
#
#   results-path  — absolute path so the CSV lands in a predictable location
#                   regardless of the working directory the plugin uses when it
#                   starts the JVM
#
#   joular-core-ringbuffer-path  — on Windows (Git Bash) the Linux default
#                   (/dev/shm/joularcorering) does not exist; override to
#                   Local\JoularCoreRing.  Java Properties.load() treats \ as
#                   an escape character, so the file must contain Local\\JoularCoreRing.

RUNTIME_PROPS=$(mktemp --suffix=.properties)
cat "$AGENT_PROPS_BASE" > "$RUNTIME_PROPS"

if command -v cygpath >/dev/null 2>&1; then
  # Windows / Git Bash: convert paths and override ring-buffer path only
  AGENT_JAR_M=$(cygpath -m "$AGENT_JAR")
  RUNTIME_PROPS_M=$(cygpath -m "$RUNTIME_PROPS")
  printf 'joular-core-ringbuffer-path=Local\\\\JoularCoreRing\n' >> "$RUNTIME_PROPS"
  log "Ring-buffer path overridden for Windows: Local\\JoularCoreRing"
else
  AGENT_JAR_M="$AGENT_JAR"
  RUNTIME_PROPS_M="$RUNTIME_PROPS"
fi

# ─── Shared plugin flags ─────────────────────────────────────────────────────

GREENER_FLAGS=(
  # Start app on the reserved free port; enable actuator /shutdown so the
  # plugin can stop it gracefully instead of force-killing after 30 s
  "-Dgreener.appArgs=--server.port=$APP_PORT --management.endpoint.shutdown.enabled=true"
  "-Dgreener.baseUrl=http://localhost:$APP_PORT"
  "-Dgreener.commitSha=$GIT_SHA"
  "-Dgreener.branch=$GIT_BRANCH"
  "-Dgreener.externalTrainingScriptFile=$WORKLOAD"
  "-Dgreener.warmupDurationSeconds=10"
  "-Dgreener.measureDurationSeconds=60"
  "-Dgreener.iterations=5"
  "-Dgreener.baselineFile=$BASELINE"
  "-Dgreener.reportOutputDir=$REPORT_DIR"
  "-Dgreener.failOnRegression=false"
  "-Dgreener.threshold=10"
  # JoularCode Java agent — plugin pre-starts JoularCore in ring-buffer mode
  # before the JVM, then attaches this agent to the Spring Boot process
  "-Dgreener.joularCodeJavaAgentPath=$AGENT_JAR_M"
  "-Dgreener.joularCodeJavaConfigPath=$RUNTIME_PROPS_M"
)

cd "$PETCLINIC_DIR"

# ─── Step 1: Doctor ──────────────────────────────────────────────────────────

step 1 "Preflight check (greener:doctor)"
log "Verifying environment: RAPL access, JoularCore binary, workload script..."
bash ./mvnw -q "${GREENER}:doctor" "${GREENER_FLAGS[@]}" -Dgreener.doctor.failOnError=false || true

# ─── Step 2: Build ───────────────────────────────────────────────────────────

step 2 "Build Spring PetClinic"
log "Packaging fat-jar (skipped if JAR already exists)..."
JAR=$(ls target/spring-petclinic-*.jar 2>/dev/null | grep -v sources | head -1 || true)
if [ -z "$JAR" ]; then
  bash ./mvnw -ntp package -DskipTests
  JAR=$(ls target/spring-petclinic-*.jar 2>/dev/null | grep -v sources | head -1)
else
  log "Reusing existing JAR: $(basename "$JAR")"
fi
log "JAR: $JAR"

# ─── Clean ───────────────────────────────────────────────────────────────────

log "Cleaning previous run artifacts..."
# On Windows, app-stdout.log / app-stderr.log inside reports/script/work/ may
# still be locked by a previous run's Java process.  Tolerate busy files and
# continue — the plugin will overwrite them during this run.
rm -rf "$REPORT_DIR" 2>/dev/null \
  || log "NOTE: some report files are still locked from the previous run — they will be overwritten."
rm -f "$BASELINE" "$DEMO_DIR/energy-baseline-trend.json"

# ─── Step 3: First measurement ────────────────────────────────────────────────────────

step 3 "First energy measurement with JoularCode Java agent"
log "Running: ${GREENER}:measure"
log "  - JoularCode Java agent is attached to the Spring Boot JVM"
log "  - Plugin pre-starts JoularCore in ring-buffer mode before the JVM"
log "  - App starts, workload runs (10 s warmup + 60 s measurement)"
log "  - Per-method energy written to: $RESULTS_DIR/"
log "  - HTML report written to: $REPORT_DIR/"
echo ""

bash ./mvnw "${GREENER}:measure" "${GREENER_FLAGS[@]}"

log "Report:"
find "$REPORT_DIR" -type f -name "greener-energy-report.html" 2>/dev/null \
  || echo "  (no report file found)"

show_method_results
# Refresh timestamp so the step-5 archive gets a different name
RUN_TS=$(date +%Y%m%d-%H%M%S)

# ─── Step 4: Save as baseline ────────────────────────────────────────────────

step 4 "Save result as energy baseline"
log "Running: ${GREENER}:update-baseline"
log "  - Promotes the latest measurement to energy-baseline.json"
log "  - Subsequent runs compare against this snapshot"
echo ""
bash ./mvnw "${GREENER}:update-baseline" \
  "-Dgreener.baselineFile=$BASELINE" \
  "-Dgreener.reportOutputDir=$REPORT_DIR" \
  "-Dgreener.commitSha=$GIT_SHA" \
  "-Dgreener.branch=$GIT_BRANCH"

if [ -f "$BASELINE" ]; then
  log "Baseline saved: $BASELINE"
  echo ""
  cat "$BASELINE"
fi

# ─── Step 5: Second measurement (regression detection) ───────────────────────

step 5 "Second measurement — regression detection against baseline"
log "Running: ${GREENER}:measure (compares against baseline, JoularCode agent active)"
log "  - A WARNING is logged when energy exceeds the threshold"
log "  - Set -Dgreener.failOnRegression=true to fail the build on regression"
log "  - Set -Dgreener.iterations=5 for statistical regression detection"
echo ""

bash ./mvnw "${GREENER}:measure" "${GREENER_FLAGS[@]}"

log "Report:"
find "$REPORT_DIR" -type f -name "greener-energy-report.html" 2>/dev/null \
  || echo "  (no report file found)"

show_method_results

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " Demo complete"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Report        : $REPORT_DIR/"
echo "  Method energy : $RESULTS_DIR/"
echo "  Baseline      : $BASELINE"
echo ""
