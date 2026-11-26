#!/usr/bin/env bash
set -euo pipefail

GAME_DIR="${GAME_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells}"

if [ ! -d "$GAME_DIR" ]; then
  echo "Error: Dead Cells directory not found at: $GAME_DIR" >&2
  exit 1
fi

if [ -f "$GAME_DIR/deadcells.x86.sh" ]; then
  mv -f "$GAME_DIR/deadcells.x86.sh" "$GAME_DIR/deadcells"
  chmod +x "$GAME_DIR/deadcells"
  echo "Restored previous x86_64 launcher wrapper."
elif [ -f "$GAME_DIR/deadcells.real" ]; then
  mv -f "$GAME_DIR/deadcells.real" "$GAME_DIR/deadcells"
  chmod +x "$GAME_DIR/deadcells"
  echo "Restored original x86_64 binary (deadcells)."
else
  echo "Warning: No deadcells.real or deadcells.x86.sh backup found; leaving current launcher untouched." >&2
fi

rm -rf "$GAME_DIR/arm64"
echo "Removed $GAME_DIR/arm64"
