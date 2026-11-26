#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASHLINK_DIR="$ROOT/hashlink"
HLSTEAM_DIR="$ROOT/libsrc/hlsteam"

HASHLINK_COMMIT="c095bc1"
HLSTEAM_COMMIT="6ae3286"

if [ ! -d "$HASHLINK_DIR/.git" ]; then
  echo "Cloning HaxeFoundation/hashlink (PR #932)..."
  git clone https://github.com/HaxeFoundation/hashlink.git "$HASHLINK_DIR"
  git -C "$HASHLINK_DIR" fetch origin pull/932/head:pr932
  git -C "$HASHLINK_DIR" checkout "$HASHLINK_COMMIT" 2>/dev/null || git -C "$HASHLINK_DIR" checkout pr932
fi

if git -C "$HASHLINK_DIR" apply --check "$ROOT/patches/hashlink.patch" 2>/dev/null; then
  echo "Applying patches/hashlink.patch..."
  git -C "$HASHLINK_DIR" apply "$ROOT/patches/hashlink.patch"
else
  echo "patches/hashlink.patch already applied (or tree modified); skipping."
fi

if [ ! -d "$HLSTEAM_DIR/.git" ]; then
  echo "Cloning HeapsIO/hlsteam..."
  mkdir -p "$(dirname "$HLSTEAM_DIR")"
  git clone https://github.com/HeapsIO/hlsteam.git "$HLSTEAM_DIR"
  git -C "$HLSTEAM_DIR" checkout "$HLSTEAM_COMMIT"
fi

if git -C "$HLSTEAM_DIR" apply --check "$ROOT/patches/hlsteam.patch" 2>/dev/null; then
  echo "Applying patches/hlsteam.patch..."
  git -C "$HLSTEAM_DIR" apply "$ROOT/patches/hlsteam.patch"
else
  echo "patches/hlsteam.patch already applied (or tree modified); skipping."
fi

echo "Upstream dependencies are ready."
