#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# run-all-demos.sh — Run all five green-coding demos in sequence
# ══════════════════════════════════════════════════════════════════════════════
#
# USAGE
#   bash run-all-demos.sh            # run all demos 01–05
#   bash run-all-demos.sh 02 04      # run only demos 02 and 04
#
# Each demo is called directly so it runs in its own subshell with its own
# EXIT trap / cleanup, keeping the demos fully isolated from each other.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

DEMOS_DIR="$(cd "$(dirname "$0")" && pwd)"

ALL_DEMOS=(
  "01-joularcore"
  "02-joularjx"
  "03-joularcode-java"
  "04-greener-maven-plugin"
  "05-greener-maven-plugin-joularcode"
)

# If arguments were given, filter to only the requested demo numbers
if [ $# -gt 0 ]; then
  SELECTED=()
  for num in "$@"; do
    matched=false
    for demo in "${ALL_DEMOS[@]}"; do
      if [[ "$demo" == "$num"* ]]; then
        SELECTED+=("$demo")
        matched=true
        break
      fi
    done
    if ! $matched; then
      echo "WARNING: no demo matching '$num' — skipping" >&2
    fi
  done
  ALL_DEMOS=("${SELECTED[@]}")
fi

PASSED=()
FAILED=()

for demo in "${ALL_DEMOS[@]}"; do
  script="$DEMOS_DIR/$demo/demo.sh"

  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo " Starting: $demo"
  echo "══════════════════════════════════════════════════════════════════════"

  if [ ! -f "$script" ]; then
    echo "ERROR: $script not found — skipping" >&2
    FAILED+=("$demo (script not found)")
    continue
  fi

  if bash "$script"; then
    PASSED+=("$demo")
  else
    rc=$?
    echo ""
    echo "ERROR: $demo exited with code $rc" >&2
    FAILED+=("$demo (exit $rc)")
  fi
done

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo " All-demos summary"
echo "══════════════════════════════════════════════════════════════════════"

if [ ${#PASSED[@]} -gt 0 ]; then
  echo " PASSED (${#PASSED[@]}):"
  for d in "${PASSED[@]}"; do echo "   ✓  $d"; done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo " FAILED (${#FAILED[@]}):"
  for d in "${FAILED[@]}"; do echo "   ✗  $d"; done
  echo ""
  exit 1
fi

echo ""
echo " All demos completed successfully."
