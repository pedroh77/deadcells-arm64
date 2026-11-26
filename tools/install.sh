#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
GAME_DIR="${GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells}"

if [ ! -d "$DIST" ] || [ ! -x "$DIST/hl" ]; then
  echo "Building dist/ package first..."
  "$ROOT/tools/package.sh"
fi

if [ ! -d "$GAME_DIR" ]; then
  echo "Error: Dead Cells directory not found at: $GAME_DIR" >&2
  exit 1
fi

mkdir -p "$GAME_DIR/arm64"

# Keep an already-installed Steamworks redistributable, since it may not be
# part of dist/ (Valve's dylib is proprietary and never shipped in releases).
steam_api_backup=""
if [ -f "$GAME_DIR/arm64/libsteam_api.dylib" ]; then
  steam_api_backup="$(mktemp -d)/libsteam_api.dylib"
  cp -f "$GAME_DIR/arm64/libsteam_api.dylib" "$steam_api_backup"
fi

rsync -a --delete "$DIST/" "$GAME_DIR/arm64/"

if [ -n "$steam_api_backup" ] && [ ! -f "$GAME_DIR/arm64/libsteam_api.dylib" ]; then
  cp -f "$steam_api_backup" "$GAME_DIR/arm64/libsteam_api.dylib"
fi

if [ ! -f "$GAME_DIR/arm64/libsteam_api.dylib" ]; then
  "$ROOT/tools/setup-steam-api.sh" "$GAME_DIR/arm64" ||
    echo "warning: no arm64 libsteam_api.dylib installed; Steam features (cloud saves, achievements) will not work" >&2
fi

# Ensure original x86_64 binary is backed up as deadcells.real
if [ -f "$GAME_DIR/deadcells" ] && file "$GAME_DIR/deadcells" | grep -q "Mach-O"; then
  cp -p "$GAME_DIR/deadcells" "$GAME_DIR/deadcells.real"
fi

# Backup previous wrapper script if present
if [ -f "$GAME_DIR/deadcells" ] && ! file "$GAME_DIR/deadcells" | grep -q "Mach-O"; then
  cp -p "$GAME_DIR/deadcells" "$GAME_DIR/deadcells.x86.sh"
fi

cat > "$GAME_DIR/deadcells" <<'EOF'
#!/bin/sh
# Uncomment for Switch Pro / Nintendo-layout controllers to use positional face buttons:
# export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
cd "$(dirname "$0")"
exec ./arm64/hl hlboot.dat "$@"
EOF
chmod +x "$GAME_DIR/deadcells"

# Clear macOS Gatekeeper quarantine flags if installed from a downloaded archive
xattr -cr "$GAME_DIR/arm64" "$GAME_DIR/deadcells" 2>/dev/null || true

echo "Installed native ARM64 runtime to: $GAME_DIR/arm64"
echo "Updated launcher wrapper: $GAME_DIR/deadcells"
