#!/usr/bin/env bash
# Install JoularCore 0.0.1-beta-4 for Linux (x86_64)
# Installs joularcore binary to /usr/local/bin/

VERSION="0.0.1-beta-4"
ZIP_NAME="binaries-linux-x86_64.zip"
DOWNLOAD_URL="https://github.com/joular/joularcore/releases/download/$VERSION/$ZIP_NAME"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)

log() { echo ""; echo "==> $*"; }

log "Platform: Linux ($(uname -m))"
log "Installing JoularCore $VERSION..."

# Download
log "Downloading $DOWNLOAD_URL..."
curl -fL --progress-bar -o "$TMP_DIR/$ZIP_NAME" "$DOWNLOAD_URL"

# Extract
log "Extracting $ZIP_NAME..."
unzip -o "$TMP_DIR/$ZIP_NAME" -d "$TMP_DIR"

# Locate binary (may be at root or in a subdirectory)
BINARY=$(find "$TMP_DIR" -name "joularcore" -type f | head -1)
if [ -z "$BINARY" ]; then
  echo "ERROR: joularcore binary not found in zip contents:"
  find "$TMP_DIR" -type f
  rm -rf "$TMP_DIR"
  exit 1
fi

chmod +x "$BINARY"
log "Installing to $INSTALL_DIR/joularcore (requires sudo)..."
sudo install -m 755 "$BINARY" "$INSTALL_DIR/joularcore"
rm -rf "$TMP_DIR"

log "joularcore installed: $(which joularcore)"

# RAPL permissions
echo ""
echo "=== RAPL setup (required for energy monitoring) ==="
echo ""
echo "  Grant read access to RAPL sysfs (resets on reboot):"
echo "    sudo chmod -R a+r /sys/class/powercap/intel-rapl"

