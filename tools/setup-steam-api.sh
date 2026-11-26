#!/usr/bin/env bash
# Installs an arm64-capable libsteam_api.dylib into the native runtime folder.
#
# Valve's Steamworks redistributable is proprietary, so it is not bundled in
# the release archive. This script looks for a copy that already exists on the
# machine (Steamworks SDK, another ARM64 Steam game, or the Steam client),
# thins it to arm64 when it is a universal binary, and copies it into place.
# Existing files are never overwritten.
#
# usage: setup-steam-api.sh [options] [target_dir]
#   --url URL    download libsteam_api.dylib from URL if no local copy is found
#   -h, --help   show this help
#
# target_dir defaults to:
#   1. $GAME_DIR/arm64 if it exists
#   2. ./arm64 if it exists (extracted release archive)
#   3. $HOME/Library/Application Support/Steam/steamapps/common/Dead Cells/arm64
set -euo pipefail

DEST_NAME="libsteam_api.dylib"
DEFAULT_GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells"
GAME_DIR="${GAME_DIR:-$DEFAULT_GAME_DIR}"
STEAM_API_URL="${STEAM_API_URL:-}"
TARGET_DIR=""

usage() {
  cat <<EOF
usage: $(basename "$0") [options] [target_dir]

Installs an arm64-capable $DEST_NAME into the native runtime folder.

options:
  --url URL    download $DEST_NAME from URL if no local copy is found
  -h, --help   show this help

target_dir defaults to:
  1. \$GAME_DIR/arm64 if it exists
  2. ./arm64 if it exists (extracted release archive)
  3. $DEFAULT_GAME_DIR/arm64
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --url)
      [ $# -ge 2 ] || { echo "error: --url needs a value" >&2; exit 2; }
      STEAM_API_URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [ -n "$TARGET_DIR" ]; then
  :
elif [ -d "$GAME_DIR/arm64" ]; then
  TARGET_DIR="$GAME_DIR/arm64"
elif [ -d "./arm64" ]; then
  TARGET_DIR="./arm64"
else
  TARGET_DIR="$GAME_DIR/arm64"
fi

dest="$TARGET_DIR/$DEST_NAME"

if [ -f "$dest" ]; then
  echo "Already present: $dest"
  exit 0
fi

if ! [ -d "$TARGET_DIR" ]; then
  echo "error: runtime folder not found: $TARGET_DIR" >&2
  usage >&2
  exit 1
fi

has_arm64() {
  lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "arm64"
}

steam_root="$HOME/Library/Application Support/Steam"
found=""
tmpdir=""
cleanup() { if [ -n "$tmpdir" ]; then rm -rf "$tmpdir"; fi; }
trap cleanup EXIT

try() {
  [ -n "${1:-}" ] || return 1
  [ -f "$1" ] || return 1
  has_arm64 "$1" || return 1
  found="$1"
}

# 1. Steamworks SDK, or an explicit path, if present anywhere on the machine.
sdk_paths=(
  "${STEAM_API_PATH:-}"
  "${STEAMWORKS_SDK:-}/redistributable_bin/osx/$DEST_NAME"
  "$HOME/steamworks/sdk/redistributable_bin/osx/$DEST_NAME"
  "$HOME/Steamworks/sdk/redistributable_bin/osx/$DEST_NAME"
)
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk_paths+=(
  "$root/libsrc/hlsteam/sdk/redistributable_bin/osx/$DEST_NAME"
  "$root/libsrc/sdkci/steamworks_sdk/redistributable_bin/osx/$DEST_NAME"
)
for c in "${sdk_paths[@]}"; do
  try "$c" && break
done

# 2. Another installed Steam game (any library folder, including external drives).
libraries=("$steam_root")
while IFS= read -r p; do
  [ -n "$p" ] && libraries+=("$p")
done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$steam_root/steamapps/libraryfolders.vdf" 2>/dev/null)
for p in /Volumes/*/SteamLibrary; do
  [ -d "$p" ] && libraries+=("$p")
done

if [ -z "$found" ]; then
  for lib in "${libraries[@]}"; do
    common="$lib/steamapps/common"
    [ -d "$common" ] || continue
    while IFS= read -r c; do
      try "$c" && break
    done < <(find "$common" -maxdepth 7 -name "$DEST_NAME" -type f 2>/dev/null)
    [ -n "$found" ] && break
  done
fi

# 3. The Steam client itself ships a copy inside its app bundle.
if [ -z "$found" ]; then
  for app in "$steam_root/Steam.AppBundle" "/Applications/Steam.app" "$HOME/Applications/Steam.app"; do
    [ -d "$app" ] || continue
    while IFS= read -r c; do
      try "$c" && break
    done < <(find "$app" -maxdepth 8 -name "$DEST_NAME" -type f 2>/dev/null)
    [ -n "$found" ] && break
  done
fi

# 4. Optional explicit download (there is no public official download for this
#    dylib: Valve ships it with the SDK, the Steam client and Steam games).
if [ -z "$found" ] && [ -n "$STEAM_API_URL" ]; then
  tmpdir="$(mktemp -d)"
  echo "Downloading $DEST_NAME from $STEAM_API_URL"
  if curl -fsSL --retry 2 -o "$tmpdir/$DEST_NAME" "$STEAM_API_URL" && has_arm64 "$tmpdir/$DEST_NAME"; then
    found="$tmpdir/$DEST_NAME"
  else
    echo "warning: download failed or the file is not arm64-capable" >&2
  fi
fi

if [ -z "$found" ]; then
  cat >&2 <<EOF
error: no arm64-capable $DEST_NAME found.

Dead Cells needs Valve's Steamworks redistributable, which cannot be bundled
here. Any of these works:
  - Steamworks SDK: redistributable_bin/osx/$DEST_NAME
  - the copy inside the Steam client app bundle (it is already on this Mac if
    Steam is installed)
  - the copy shipped with another native (Apple Silicon) Steam game

If you have the file elsewhere, point the installer at it:
  STEAM_API_PATH=/path/to/$DEST_NAME $(basename "$0") "$TARGET_DIR"

Or download it from a URL you trust:
  $(basename "$0") --url https://example.com/$DEST_NAME "$TARGET_DIR"
EOF
  exit 1
fi

echo "Using: $found"
if lipo -archs "$found" 2>/dev/null | tr ' ' '\n' | grep -qx "x86_64"; then
  echo "Thinning universal binary to arm64..."
  tmpfile="$(mktemp -t libsteam_api.XXXXXX)"
  lipo -thin arm64 "$found" -output "$tmpfile"
  cp -f "$tmpfile" "$dest"
  rm -f "$tmpfile"
else
  cp -f "$found" "$dest"
fi

chmod 755 "$dest"
codesign -s - --force "$dest" >/dev/null 2>&1 || true
xattr -cr "$dest" 2>/dev/null || true

echo "Installed: $dest"
