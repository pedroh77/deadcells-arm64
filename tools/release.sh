#!/usr/bin/env bash
# Builds the release archive from dist/.
#
# Layout of the archive:
#   arm64/              native runtime (hl, libhl, .hdll plugins, third-party dylibs)
#   setup-steam-api.sh  installs an arm64 libsteam_api.dylib found on the machine
#   LICENSE             GPLv3
#
# Valve's libsteam_api.dylib is proprietary and is deliberately excluded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="${VERSION:-1.0.0}"
NAME="deadcells-arm64-v${VERSION}-macos-arm64"
OUT="${OUT_DIR:-$ROOT}/$NAME.tar.gz"

if [ ! -x "$DIST/hl" ]; then
  echo "error: dist/hl not found - run 'make dist' first" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/$NAME"
rsync -a "$DIST/" "$STAGE/$NAME/arm64/"
rm -f "$STAGE/$NAME/arm64/libsteam_api.dylib"
cp -f "$ROOT/tools/setup-steam-api.sh" "$STAGE/$NAME/setup-steam-api.sh"
cp -f "$ROOT/LICENSE" "$STAGE/$NAME/LICENSE"
chmod 755 "$STAGE/$NAME/setup-steam-api.sh"

# Normalize metadata and drop macOS junk
find "$STAGE/$NAME" -name ".DS_Store" -delete
find "$STAGE/$NAME" -exec touch -h -t 202001010000 {} +

( cd "$STAGE" && tar --format ustar -czf "$OUT" "$NAME" )

echo "Release archive: $OUT"
ls -lh "$OUT"
