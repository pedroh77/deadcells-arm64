#!/usr/bin/env bash
# Dead Cells — native Apple Silicon (arm64) runtime installer.
#
# Installs the runtime shipped next to this script on top of a Steam copy of
# Dead Cells. The install is non-destructive: the original launcher is kept as
# deadcells.real and the runtime lives in arm64/, so it can be reverted at any
# time with --uninstall.
#
# usage: ./install.sh [options]
#
#   --game-dir PATH       Dead Cells folder (default: auto-detect)
#   --steam-api-url URL   download libsteam_api.dylib from URL if no local copy
#   -y, --yes             don't wait for confirmation
#   --uninstall           restore the original launcher and remove arm64/
#   -h, --help            show this help
#
# Examples:
#   ./install.sh
#   ./install.sh --game-dir "/Volumes/Games/SteamLibrary/steamapps/common/Dead Cells"
#   ./install.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells"

GAME_DIR="${GAME_DIR:-}"
STEAM_API_URL="${STEAM_API_URL:-}"
UNINSTALL=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --game-dir)
      [ $# -ge 2 ] || { echo "error: --game-dir needs a path" >&2; exit 2; }
      GAME_DIR="$2"
      shift 2
      ;;
    --steam-api-url)
      [ $# -ge 2 ] || { echo "error: --steam-api-url needs a URL" >&2; exit 2; }
      STEAM_API_URL="$2"
      shift 2
      ;;
    -y|--yes)
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# --- locate our own files (release archive layout or repo layout) ------------
if [ -x "$ROOT/arm64/hl" ]; then
  RUNTIME="$ROOT/arm64"
elif [ -x "$ROOT/dist/hl" ]; then
  RUNTIME="$ROOT/dist"
else
  echo "error: no arm64 runtime next to this script (expected $ROOT/arm64/hl)" >&2
  exit 1
fi

LAUNCHER=""
for f in "$ROOT/launcher" "$ROOT/tools/launcher"; do
  [ -f "$f" ] && { LAUNCHER="$f"; break; }
done
[ -n "$LAUNCHER" ] || { echo "error: launcher script not found next to this script" >&2; exit 1; }

STEAM_HELPER=""
for f in "$ROOT/setup-steam-api.sh" "$ROOT/tools/setup-steam-api.sh"; do
  [ -x "$f" ] && { STEAM_HELPER="$f"; break; }
done

if [ "$(uname -m)" != "arm64" ]; then
  echo "warning: this shell is not arm64 ($(uname -m)); the runtime only runs on Apple Silicon." >&2
fi

# --- find the game folder ----------------------------------------------------
steam_root="$HOME/Library/Application Support/Steam"

game_dir_candidates() {
  printf '%s\n' "$DEFAULT_GAME_DIR"
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && printf '%s/steamapps/common/Dead Cells\n' "$p"
  done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$steam_root/steamapps/libraryfolders.vdf" 2>/dev/null)
  for p in /Volumes/*/SteamLibrary; do
    [ -d "$p" ] && printf '%s/steamapps/common/Dead Cells\n' "$p"
  done
}

if [ -z "$GAME_DIR" ]; then
  while IFS= read -r candidate; do
    if [ -f "$candidate/hlboot.dat" ]; then
      GAME_DIR="$candidate"
      break
    fi
  done < <(game_dir_candidates)

  if [ -z "$GAME_DIR" ]; then
    if [ ! -t 0 ]; then
      echo "error: Dead Cells folder not found; pass --game-dir PATH" >&2
      exit 1
    fi
    echo "Dead Cells folder not found automatically."
    printf 'Drag the Dead Cells folder here, or paste its path: '
    IFS= read -r answer || true
    answer="${answer%\"}"
    answer="${answer#\"}"
    answer="${answer//\\ / }"
    GAME_DIR="${answer%/}"
  fi
fi

GAME_DIR="${GAME_DIR%/}"

if [ ! -d "$GAME_DIR" ]; then
  echo "error: not a directory: $GAME_DIR" >&2
  exit 1
fi

# --- uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$GAME_DIR/deadcells.real" ]; then
    mv -f "$GAME_DIR/deadcells.real" "$GAME_DIR/deadcells"
    chmod 755 "$GAME_DIR/deadcells"
    echo "Restored the original launcher: $GAME_DIR/deadcells"
  else
    echo "warning: no deadcells.real backup found; leaving the current launcher alone." >&2
  fi
  rm -rf "$GAME_DIR/arm64"
  echo "Removed $GAME_DIR/arm64"
  echo "Dead Cells is back on the Steam (x86_64) build."
  exit 0
fi

# --- sanity checks -----------------------------------------------------------
if [ ! -f "$GAME_DIR/hlboot.dat" ]; then
  echo "error: $GAME_DIR doesn't look like a Dead Cells install (no hlboot.dat)." >&2
  echo "       Verify the game files in Steam, or pass --game-dir PATH." >&2
  exit 1
fi

if [ ! -f "$GAME_DIR/res.pak" ]; then
  echo "warning: res.pak not found in $GAME_DIR (is the game fully installed?)" >&2
fi

echo "Game folder: $GAME_DIR"
echo "Runtime:     $RUNTIME"

# --- 1. native runtime -------------------------------------------------------
mkdir -p "$GAME_DIR/arm64"
if command -v rsync >/dev/null 2>&1; then
  # --exclude keeps an already installed libsteam_api.dylib in place
  rsync -a --delete --exclude "libsteam_api.dylib" "$RUNTIME/" "$GAME_DIR/arm64/"
else
  cp -R "$RUNTIME/." "$GAME_DIR/arm64/"
fi
echo "Installed runtime: $GAME_DIR/arm64"

# --- 2. Steamworks runtime ---------------------------------------------------
if [ ! -f "$GAME_DIR/arm64/libsteam_api.dylib" ]; then
  if [ -z "$STEAM_HELPER" ]; then
    echo "error: setup-steam-api.sh not found next to this script" >&2
    exit 1
  fi
  if [ -n "$STEAM_API_URL" ]; then
    "$STEAM_HELPER" --url "$STEAM_API_URL" "$GAME_DIR/arm64" || { echo "error: could not install libsteam_api.dylib" >&2; exit 1; }
  else
    "$STEAM_HELPER" "$GAME_DIR/arm64" || { echo "error: could not install libsteam_api.dylib" >&2; exit 1; }
  fi
else
  echo "Steamworks runtime already present: arm64/libsteam_api.dylib"
fi

# --- 3. launcher -------------------------------------------------------------
if [ -f "$GAME_DIR/deadcells" ] && ! head -c 2 "$GAME_DIR/deadcells" 2>/dev/null | grep -q '#!'; then
  mv -f "$GAME_DIR/deadcells" "$GAME_DIR/deadcells.real"
  echo "Backed up the original launcher: deadcells.real"
elif [ ! -f "$GAME_DIR/deadcells.real" ]; then
  echo "warning: no original deadcells launcher found; nothing to back up." >&2
fi

cp -f "$LAUNCHER" "$GAME_DIR/deadcells"
chmod 755 "$GAME_DIR/deadcells"
echo "Installed launcher: $GAME_DIR/deadcells"

# --- 4. Gatekeeper quarantine ------------------------------------------------
xattr -cr "$GAME_DIR/arm64" "$GAME_DIR/deadcells" 2>/dev/null || true

cat <<EOF

Done. Launch Dead Cells from Steam as usual.

  runtime     $GAME_DIR/arm64
  original    $GAME_DIR/deadcells.real
  to revert   $(basename "$0") --uninstall

Switch Pro / Nintendo-layout controller? Add this line to $GAME_DIR/deadcells:
  export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
EOF
