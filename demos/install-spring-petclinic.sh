#!/usr/bin/env bash
# install-spring-petclinic.sh
# Add spring-petclinic as a git submodule (or update it if already present).
#
# If spring-petclinic is currently tracked as regular files in this repo,
# this script will remove it from git tracking and re-add it as a submodule.
#
# Usage:
#   chmod +x install-spring-petclinic.sh
#   ./install-spring-petclinic.sh

set -euo pipefail

REPO_URL="git@github.com:spring-projects/spring-petclinic.git"
SUBMODULE_PATH="demos/spring-petclinic"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { echo ""; echo "==> $*"; }
warn() { echo ""; echo "WARN: $*"; }
die()  { echo ""; echo "ERROR: $*" >&2; exit 1; }

# Must run from a git repo root
[ -d "$ROOT_DIR/.git" ] \
  || die "No .git directory found at $ROOT_DIR. Run this from inside the repository."

cd "$ROOT_DIR"

if git config --file .gitmodules --get "submodule.${SUBMODULE_PATH}.url" >/dev/null 2>&1; then
  log "Submodule already registered: ${SUBMODULE_PATH}"
  log "Initialising and updating submodule..."
  git submodule update --init --recursive "$SUBMODULE_PATH"
else
  # Check if the directory is currently tracked as plain files
  if git ls-files --error-unmatch "${SUBMODULE_PATH}/pom.xml" >/dev/null 2>&1; then
    warn "${SUBMODULE_PATH} is currently tracked as regular files."
    warn "It will be removed from git tracking and re-added as a submodule."
    echo ""
    read -r -p "Continue? [y/N] " _confirm
    [[ "$_confirm" =~ ^[Yy]$ ]] || exit 0

    log "Removing ${SUBMODULE_PATH} from git index (keeping local files)..."
    git rm -r --cached "$SUBMODULE_PATH"

    log "Deleting local directory to allow clean submodule checkout..."
    rm -rf "$SUBMODULE_PATH"
  fi

  log "Adding submodule: ${REPO_URL} -> ${SUBMODULE_PATH}"
  git submodule add "$REPO_URL" "$SUBMODULE_PATH"
  log "Initialising submodule..."
  git submodule update --init --recursive "$SUBMODULE_PATH"
fi

log "spring-petclinic is ready at: ${ROOT_DIR}/${SUBMODULE_PATH}"
