#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BIN="$ROOT/hashlink/build-libs/bin"
if [ -z "${BREW:-}" ]; then
  BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)/opt"
fi

rm -rf "$DIST"
mkdir -p "$DIST"

# 1. Copy HashLink VM & .hdll plugins
cp -f "$BIN/hl" "$DIST/hl"
cp -f "$BIN/libhl.2.0.0.dylib" "$DIST/libhl.2.dylib"
ln -sf "libhl.2.dylib" "$DIST/libhl.dylib"

for hdll in fmt openal sdl ssl steam ui uv; do
  cp -f "$BIN/${hdll}.hdll" "$DIST/${hdll}.hdll"
done

# 2. Copy third-party ARM64 .dylib dependencies
DYLIBS=(
  "$BIN/libsteam_api.dylib"
  "$BREW/sdl2/lib/libSDL2-2.0.0.dylib"
  "$BREW/sdl3/lib/libSDL3.0.dylib"
  "$BREW/openal-soft/lib/libopenal.1.dylib"
  "$BREW/libpng/lib/libpng16.16.dylib"
  "$BREW/jpeg-turbo/lib/libturbojpeg.0.dylib"
  "$BREW/libogg/lib/libogg.0.dylib"
  "$BREW/libvorbis/lib/libvorbis.0.dylib"
  "$BREW/libvorbis/lib/libvorbisfile.3.dylib"
  "$BREW/libvorbis/lib/libvorbisenc.2.dylib"
  "$BREW/mbedtls@3/lib/libmbedtls.21.dylib"
  "$BREW/mbedtls@3/lib/libmbedx509.7.dylib"
  "$BREW/mbedtls@3/lib/libmbedcrypto.16.dylib"
  "$BREW/libuv/lib/libuv.1.dylib"
)

missing=()
for d in "${DYLIBS[@]}"; do
  if [ ! -f "$d" ]; then
    missing+=("$d")
    continue
  fi
  base="$(basename "$d")"
  cp -f "$d" "$DIST/$base"
  chmod 755 "$DIST/$base"
done
ln -sf "libSDL3.0.dylib" "$DIST/libSDL3.dylib"

# A partial bundle is worse than no bundle: refuse to ship one.
if [ ${#missing[@]} -gt 0 ]; then
  echo "error: missing ARM64 dependencies (run 'make setup' / install the Homebrew packages or set BREW):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

chmod 755 "$DIST/hl" "$DIST/libhl.2.dylib" "$DIST"/*.hdll

# 3. Rewrite install names and @rpath so dist/ is 100% self-contained
install_name_tool -add_rpath "@executable_path" "$DIST/hl" 2>/dev/null || true

for f in "$DIST/hl" "$DIST"/*.dylib "$DIST"/*.hdll; do
  [ -L "$f" ] && continue
  base="$(basename "$f")"
  if [[ "$base" != "hl" ]]; then
    install_name_tool -id "@rpath/$base" "$f"
    install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
  fi
  # Rewrite any /opt/homebrew or /opt/local references
  while read -r dep; do
    [ -z "$dep" ] && continue
    dep_base="$(basename "$dep")"
    if [[ "$dep" == "/opt/local/lib/libz.1.dylib" ]]; then
      install_name_tool -change "$dep" "/usr/lib/libz.1.dylib" "$f"
    elif [[ "$dep" == /opt/homebrew/* ]]; then
      install_name_tool -change "$dep" "@rpath/$dep_base" "$f"
    fi
  done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')

  # Drop every rpath that is not relative to the bundle: build-tree and
  # Homebrew paths must never leak into the shipped binaries.
  rpaths="$(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}')"
  for rp in $rpaths; do
    case "$rp" in
      "@executable_path" | "@loader_path") ;;
      *)
        echo "  removing rpath $rp from $base"
        install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
        ;;
    esac
  done

  codesign -s - --force "$f" >/dev/null 2>&1 || true
done

# 4. Sanity check: no machine-specific path may survive in the bundle
leaks="$(otool -l "$DIST"/hl "$DIST"/*.dylib "$DIST"/*.hdll 2>/dev/null |
  awk '/LC_RPATH/{getline; getline; print $2}' | grep -v '^@' || true)"
if [ -n "$leaks" ]; then
  echo "error: non-relocatable rpaths left in dist/:" >&2
  echo "$leaks" >&2
  exit 1
fi

echo "Packaged ARM64 build in $DIST"
