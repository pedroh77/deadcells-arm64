#!/usr/bin/env bash
# Installs an arm64-capable libsteam_api.dylib into the native runtime folder.
#
# Valve's Steamworks redistributable is proprietary, so it is intentionally not
# bundled in the release archive. This script looks for a copy that already
# exists on the machine (Steamworks SDK, the Steam client, or another ARM64
# Steam game), thins it to arm64 when it is a universal binary, and copies it
# into the runtime folder. Existing files are never overwritten.
#
# usage: setup-steam-api.sh [target_dir]
set -euo pipefail

DEFAULT_GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells"
GAME_DIR="${GAME_DIR:-$DEFAULT_GAME_DIR}"
DEST_NAME="libsteam_api.dylib"

usage() {
  cat <<EOF
usage: $(basename "$0") [target_dir]

target_dir defaults to:
  1. \$GAME_DIR/arm64 if it exists
  2. ./arm64 if it exists (extracted release archive)
  3. $DEFAULT_GAME_DIR/arm64
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

if [ -n "${1:-}" ]; then
  TARGET_DIR="$1"
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

# Candidate locations: an explicit SDK first, then repo-local checkouts, then
# any other installed Steam game, and finally the Steam client itself.
candidates=(
  "${STEAMWORKS_SDK:-}/redistributable_bin/osx/$DEST_NAME"
  "$HOME/steamworks/sdk/redistributable_bin/osx/$DEST_NAME"
  "$GAME_DIR/$DEST_NAME"
)

# Repo-local checkouts of the SDK (when running from a source checkout).
root="$(cd "$(dirname "$0")/.." && pwd)"
candidates+=(
  "$root/libsrc/hlsteam/sdk/redistributable_bin/osx/$DEST_NAME"
  "$root/libsrc/sdkci/steamworks_sdk/redistributable_bin/osx/$DEST_NAME"
)

found=""
for c in "${candidates[@]}"; do
  [ -n "$c" ] || continue
  if [ -f "$c" ] && has_arm64 "$c"; then
    found="$c"
    break
  fi
done

# Other installed Steam games are the most common source on a player machine.
if [ -z "$found" ] && [ -d "$GAME_DIR/../" ]; then
  while IFS= read -r c; do
    if has_arm64 "$c"; then
      found="$c"
      break
    fi
  done < <(find "$GAME_DIR/.." -maxdepth 7 -name "$DEST_NAME" -type f 2>/dev/null)
fi

# Last resort: the Steam client app bundle ships its own copy.
if [ -z "$found" ]; then
  steam_client="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/Frameworks/Steam Helper.app/Contents/MacOS/$DEST_NAME"
  if [ -f "$steam_client" ] && has_arm64 "$steam_client"; then
    found="$steam_client"
  fi
fi

if [ -z "$found" ]; then
  cat >&2 <<EOF
error: no arm64-capable $DEST_NAME found.

Dead Cells needs Valve's Steamworks redistributable, which cannot be bundled
here. Any of these works:
  - Steamworks SDK (https://partner.steamgames.com/downloads/steamworks_sdk.zip),
    file redistributable_bin/osx/$DEST_NAME
  - the copy shipped with another native (Apple Silicon) Steam game
  - the copy inside the Steam client app bundle

Re-run with the SDK location:
  STEAMWORKS_SDK=/path/to/sdk $0 "$TARGET_DIR"

Or copy the file manually:
  cp /path/to/$DEST_NAME "$TARGET_DIR/"
EOF
  exit 1
fi

echo "Found: $found"
archs="$(lipo -archs "$found" 2>/dev/null || echo arm64)"
if echo "$archs" | tr ' ' '\n' | grep -qx "x86_64"; then
  echo "Thinning universal binary to arm64..."
  tmp="$(mktemp -t libsteam_api.XXXXXX)"
  lipo -thin arm64 "$found" -output "$tmp"
  cp -f "$tmp" "$dest"
  rm -f "$tmp"
else
  cp -f "$found" "$dest"
fi

chmod 755 "$dest"
codesign -s - --force "$dest" >/dev/null 2>&1 || true
xattr -cr "$dest" 2>/dev/null || true

echo "Installed: $dest"
