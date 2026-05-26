#!/usr/bin/env bash
# install-gatling.sh — download and install Gatling standalone (OSS)
#
# Installs to: $HOME/.local/gatling
# Adds wrapper: $HOME/.local/bin/gatling.sh  (run from any directory)
# Appends GATLING_HOME export to ~/.bashrc / ~/.bash_profile
#
# Usage:
#   bash demos/install-gatling.sh           # installs default version
#   GATLING_VERSION=3.14.9.1 bash demos/install-gatling.sh

set -euo pipefail

GATLING_VERSION="${GATLING_VERSION:-3.14.9.1}"
BUNDLE="gatling-charts-highcharts-bundle-${GATLING_VERSION}"
BUNDLE_ZIP="${BUNDLE}-bundle.zip"
MAVEN_BASE="https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle"
DOWNLOAD_URL="${MAVEN_BASE}/${GATLING_VERSION}/${BUNDLE_ZIP}"

INSTALL_DIR="$HOME/.local/gatling"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/gatling.sh"

log() { echo ""; echo "==> $*"; }

# ── prerequisites ─────────────────────────────────────────────────────────────
for tool in curl unzip java; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is required but not found. Install it first."
    exit 1
  fi
done

# ── download ──────────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "Downloading Gatling ${GATLING_VERSION}..."
curl -fL --progress-bar -o "$TMP/$BUNDLE_ZIP" "$DOWNLOAD_URL"

log "Extracting..."
unzip -q "$TMP/$BUNDLE_ZIP" -d "$TMP"

# ── install ───────────────────────────────────────────────────────────────────
# The top-level directory name inside the zip can vary across versions;
# discover it instead of assuming it matches the zip name.
EXTRACTED=$(find "$TMP" -maxdepth 1 -mindepth 1 -type d | head -1)
if [ -z "$EXTRACTED" ]; then
  echo "ERROR: zip extracted no directory — contents of $TMP:"
  ls "$TMP"
  exit 1
fi

log "Installing to $INSTALL_DIR..."
mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR"
mv "$EXTRACTED" "$INSTALL_DIR"

echo "    Installed layout:"
ls "$INSTALL_DIR"

# Gatling 3.14+ ships as a Maven wrapper project (offline bundle includes .m2/repository).
# Verify mvnw is present; make it executable.
if [ ! -f "$INSTALL_DIR/mvnw" ]; then
  echo "ERROR: expected mvnw in $INSTALL_DIR — unknown bundle layout."
  exit 1
fi
chmod +x "$INSTALL_DIR/mvnw"

# Ensure simulation source directory exists
mkdir -p "$INSTALL_DIR/src/test/java"

# ── wrapper in ~/.local/bin ───────────────────────────────────────────────────
# Translates classic gatling.sh flags (-sf, -s, -rf, -nr) to mvnw gatling:test.
# JAVA_OPTS -D properties are forwarded as Maven system properties.
mkdir -p "$BIN_DIR"
cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

GATLING_HOME="$HOME/.local/gatling"
SIM_FOLDER=""
SIM_CLASS=""
RESULTS_FOLDER=""
MVNW_ARGS=("gatling:test")

while [[ $# -gt 0 ]]; do
  case "$1" in
    -sf) SIM_FOLDER="$2"; shift 2 ;;
    -s)  SIM_CLASS="$2";  shift 2 ;;
    -rf) RESULTS_FOLDER="$2"; shift 2 ;;
    -nr) shift ;;   # no-reports: Maven plugin always shows console output; skip
    -D*) MVNW_ARGS+=("$1"); shift ;;
    *)   shift ;;
  esac
done

# Copy Java simulation sources into the Maven project
if [ -n "$SIM_FOLDER" ]; then
  find "$SIM_FOLDER" -maxdepth 1 -name "*.java" -exec cp {} "$GATLING_HOME/src/test/java/" \;
fi

[ -n "$SIM_CLASS" ]      && MVNW_ARGS+=("-Dgatling.simulationClass=$SIM_CLASS")
[ -n "$RESULTS_FOLDER" ] && MVNW_ARGS+=("-Dgatling.resultsFolder=$RESULTS_FOLDER")

# Forward -D properties from JAVA_OPTS
for _opt in ${JAVA_OPTS:-}; do
  case "$_opt" in -D*) MVNW_ARGS+=("$_opt") ;; esac
done

cd "$GATLING_HOME"
exec ./mvnw "${MVNW_ARGS[@]}"
WRAPPER_EOF
chmod +x "$WRAPPER"

# ── shell profile ─────────────────────────────────────────────────────────────
EXPORT_LINE='export GATLING_HOME="$HOME/.local/gatling"'
PATH_LINE='export PATH="$GATLING_HOME/bin:$HOME/.local/bin:$PATH"'

for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
  if [ -f "$rc" ] && ! grep -qF 'GATLING_HOME' "$rc"; then
    {
      echo ""
      echo "# Gatling (added by install-gatling.sh)"
      echo "$EXPORT_LINE"
      echo "$PATH_LINE"
    } >> "$rc"
    log "Updated $rc"
  fi
done

log "Gatling ${GATLING_VERSION} installed (Maven wrapper bundle)."
echo "  Home   : $INSTALL_DIR"
echo "  Wrapper: $WRAPPER"
echo ""
echo "Open a new terminal (or run: export GATLING_HOME=\$HOME/.local/gatling)"
echo "Test with: gatling.sh -sf demos/loadtest -s PetclinicSimulation"
