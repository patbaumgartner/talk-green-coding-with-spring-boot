#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Demo 04 — greener-spring-boot Maven plugin: build-integrated energy measurement
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT IT DOES
#   1. greener:doctor          — verify environment (RAPL access, JoularCore,
#                                workload script)
#   2. mvn package             — build the Spring PetClinic fat-jar
#   3. greener:measure         — start the app, run the workload, record energy,
#                                produce an HTML report under reports/
#   4. greener:update-baseline — promote the latest result to energy-baseline.json
#                                so subsequent runs can detect regressions
#   5. greener:measure         — second run: compare against baseline and log a
#                                WARNING when energy exceeds the threshold
#
# OUTPUT
#   reports/                    — HTML energy report (greener-energy-report.html)
#   energy-baseline.json        — baseline snapshot used for regression detection
#   energy-baseline-trend.json  — rolling trend across all runs
#
# PREREQUISITES
#   - Java 17+ with Maven wrapper   →  demos/spring-petclinic/mvnw
#   - Gatling ≥ 3.13                →  install-gatling.sh
#   - Spring PetClinic submodule    →  install-spring-petclinic.sh
#   - JoularCore (optional locally) →  auto-downloaded by the plugin to
#                                      ~/.greener/cache/ on first run
#
# Linux RAPL (run once):  sudo chmod -R a+r /sys/class/powercap/intel-rapl
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$DEMO_DIR/console.log") 2>&1
PETCLINIC_DIR="$DEMO_DIR/../spring-petclinic"
WORKLOAD="$DEMO_DIR/workload.sh"
BASELINE="$DEMO_DIR/energy-baseline.json"
REPORT_DIR="$DEMO_DIR/reports"

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

# ─── Preflight ───────────────────────────────────────────────────────────────

[ -f "$PETCLINIC_DIR/mvnw" ] \
  || die "spring-petclinic submodule not initialized." \
         "Run:  bash install-spring-petclinic.sh" \
         "  or: git submodule update --init demos/spring-petclinic"

# Capture git context so commitSha/branch are not null in the baseline JSON
GIT_SHA=$(git -C "$DEMO_DIR" rev-parse --short HEAD 2>/dev/null || echo "")
GIT_BRANCH=$(git -C "$DEMO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
# Pick a free port — same principle as --server.port=0 in demos 01-03, but we
# need to know the port upfront so we can also tell the plugin its baseUrl for
# health-checking and APP_URL injection (the plugin has no startup-log parser).
APP_PORT=$(python3 -c \
  "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
log "Using port $APP_PORT for Spring PetClinic"

# ─── Shared plugin flags ─────────────────────────────────────────────────────

# Extracted into an array so measure and update-baseline use identical settings.
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
)

cd "$PETCLINIC_DIR"

# ─── Step 1: Doctor ──────────────────────────────────────────────────────────

step 1 "Preflight check (greener:doctor)"
log "Verifying environment: RAPL access, JoularCore binary, workload script..."
# -Dgreener.doctor.failOnError=false lets the demo continue even on partial
# failures (e.g., no RAPL on a VM) so subsequent steps can still be shown
bash ./mvnw -q "${GREENER}:doctor" -Dgreener.doctor.failOnError=false || true

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

step 3 "First energy measurement (no baseline yet — establishes initial data)"
log "Running: ${GREENER}:measure"
log "  - JoularCore is auto-downloaded to ~/.greener/cache/ if not present"
log "  - App starts, workload runs (10 s warmup + 60 s measurement)"
log "  - HTML report written to: $REPORT_DIR/"
echo ""
bash ./mvnw "${GREENER}:measure" "${GREENER_FLAGS[@]}"

log "Report:"
find "$REPORT_DIR" -type f -name "greener-energy-report.html" 2>/dev/null \
  || echo "  (no report file found)"

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
log "Running: ${GREENER}:measure (compares against baseline)"
log "  - A WARNING is logged when energy exceeds the threshold"
log "  - Set -Dgreener.failOnRegression=true to fail the build on regression"
log "  - Set -Dgreener.iterations=5 for statistical regression detection"
echo ""
bash ./mvnw "${GREENER}:measure" "${GREENER_FLAGS[@]}"

log "Report:"
find "$REPORT_DIR" -type f -name "greener-energy-report.html" 2>/dev/null \
  || echo "  (no report file found)"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " Demo complete"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Report  : $REPORT_DIR/"
echo "  Baseline: $BASELINE"
echo ""
