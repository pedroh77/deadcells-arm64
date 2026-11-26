# Dead Cells — Native macOS ARM64 (Apple Silicon) Runtime

Rebuilds the **HashLink JIT VM (`hl` + `libhl`)** and all required native `.hdll` plugins (`fmt`, `openal`, `sdl`, `ssl`, `steam`, `ui`, `uv`) natively for `arm64` on macOS, running the unmodified Steam `hlboot.dat` (HashLink v4 bytecode) and `res.pak` without Rosetta 2.

## Why?

Even though Rosetta 2 generally performs well, Dead Cells on macOS has occasional frame drops and stutters on Apple Silicon that a 2D pixel-art platformer really shouldn't have.

The main reason seems to be how the game is built: Dead Cells doesn't ship as a native compiled game binary. The actual game logic and assets live in architecture-independent files (`hlboot.dat` HashLink bytecode and `res.pak`), while the `deadcells` executable is essentially an `x86_64` HashLink JIT VM plus native `.hdll` plugins. Under Rosetta 2, macOS ends up translating `x86_64` code generated on the fly by HashLink's JIT, which creates a noticeable bottleneck.

To get around this, I built a native `arm64` runtime that runs the unmodified Steam `hlboot.dat` and `res.pak` directly on Apple Silicon without Rosetta 2.

## Results

| Metric | Original (`deadcells.real` x86_64 via Rosetta 2) | Native (`arm64/hl` Apple Silicon JIT) |
|---|---|---|
| Architecture | `x86_64` (Rosetta 2 translating JIT code) | `arm64` native (HashLink PR #932 `MAP_JIT` backend) |
| Native bindings matched | 503 / 503 | **503 / 503** (`ok=503 bad=0`) |
| 1,291 shaders load time | `1.891s` | **`0.515s` (~3.67x faster)** |
| Steam API / Cloud / Achievements | Working (`libsteam_api.dylib` x86_64) | **Working** (`libsteam_api.dylib` universal `arm64`, installed by `setup-steam-api.sh`) |
| Nintendo / Switch Pro layout fix | Optional | Optional (`SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0`) |

## Quick Install (Pre-built Release)

1. Download and extract the latest release archive from GitHub Releases (it expands to `arm64/`, `setup-steam-api.sh` and `LICENSE`).
2. Open your Steam Dead Cells folder (default: `~/Library/Application Support/Steam/steamapps/common/Dead Cells`).
3. Back up the original `deadcells` executable as `deadcells.real`.
4. Copy the extracted `arm64/` folder into the Dead Cells directory.
5. Create the `deadcells` wrapper script inside the Dead Cells directory and make it executable:
   ```sh
   #!/bin/sh
   # Uncomment for Switch Pro / Nintendo-layout controllers:
   # export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
   cd "$(dirname "$0")"
   exec ./arm64/hl hlboot.dat "$@"
   ```
   ```bash
   chmod +x deadcells
   ```
6. Clear macOS Gatekeeper quarantine attributes on the downloaded binaries:
   ```bash
   xattr -cr arm64 deadcells
   ```
7. Install Valve's Steamworks redistributable. `libsteam_api.dylib` is proprietary and **not** bundled in the release archive; the archive ships `setup-steam-api.sh`, which looks for an `arm64`-capable copy already on your machine (Steamworks SDK, the Steam client, or another ARM64 Steam game), thins it to `arm64` if it is universal, and copies it into the runtime folder:
   ```bash
   # from the extracted archive, targeting the installed runtime:
   ./setup-steam-api.sh "$HOME/Library/Application Support/Steam/steamapps/common/Dead Cells/arm64"
   ```
   Without arguments it targets your installed `$GAME_DIR/arm64` (or `./arm64` when the game folder is not found); an existing `libsteam_api.dylib` is never overwritten.

To revert, delete `arm64/` and rename `deadcells.real` back to `deadcells` (or verify game files in Steam).

## Building from Source

### Prerequisites

Install the required ARM64 libraries via Homebrew:

```bash
brew install cmake openal-soft sdl2 mbedtls@3 libuv libpng jpeg-turbo libogg libvorbis
```

You also need Valve's **Steamworks SDK** (not included in this repository). Extract it and symlink or place it at `libsrc/hlsteam/sdk` so that `libsrc/hlsteam/sdk/public` and `libsrc/hlsteam/sdk/redistributable_bin/osx/libsteam_api.dylib` exist.

### Build, Verify & Install

```bash
# Clone upstream HashLink (PR #932) & hlsteam and apply local patches
make setup

# Build dist/ and verify all 503 native signatures
make check

# Install into Dead Cells Steam folder (non-destructive: backs up deadcells.real and installs arm64/)
make install

# Restore original x86_64 launcher and remove arm64/
make uninstall

# Build the release tarball (dist/ without Valve's libsteam_api.dylib)
make release
```

## Key Technical Findings & Patches

1. **HashLink ARM64 JIT ([PR #932](https://github.com/HaxeFoundation/hashlink/pull/932))**:
   - Compiles `src/jit_aarch64.c` and `src/jit_aarch64_emit.c` with Apple Silicon `MAP_JIT` and `pthread_jit_write_protect_np` support.
   - Patched `resolve_library` ([`patches/hashlink.patch`](patches/hashlink.patch)) using `dladdr()` so `libhl.2.dylib` loads `.hdll` files from its own directory (`arm64/`) first, preventing collisions with the original `x86_64` `.hdll` files in the game's root folder.
2. **503 Native Signatures Verified ([`tools/checknatives.c`](tools/checknatives.c))**:
   - Extracted all 503 native function imports and type signatures from `hlboot.dat` into [`analysis/natives.txt`](analysis/natives.txt) (`164 std`, `126 openal`, `109 sdl`, `55 steam`, `20 ssl`, `14 fmt`, `12 ui`, `3 uv`). Note: `mysql.hdll` is shipped with the game but has 0 references in `hlboot.dat`.
3. **SDL2 Compatibility (`sdl.hdll`)**:
   - HashLink `master` migrated `libs/sdl` to SDL3, which breaks `hlboot.dat` signatures. Built `sdl.hdll` from HashLink `1.15` (`libsrc/libs/sdl`) against `SDL2` (`sdl2-compat` + `libSDL3.0.dylib`).
4. **OpenAL EFX Extensions (`openal.hdll`)**:
   - macOS's system `OpenAL.framework` lacks `ALC_EXT_EFX` (`al_gen_effects`, `al_gen_filters`, `al_gen_auxiliary_effect_slots`, etc., 33 functions required by Dead Cells). Built `openal.hdll` with `-Dopenal_soft` against `openal-soft`.
5. **Motion Twin Custom Primitives Reconstructed**:
   - **`uv@resolve` (`PXuv_loop_BiPiiB_v_b`)**: Disassembled the original `x86_64` `uv.hdll` and reimplemented Motion Twin's custom async DNS resolver (`uv_getaddrinfo` wrapper) in [`patches/hashlink.patch`](patches/hashlink.patch) (`libs/uv/uv.c`).
   - **`steam@is_user_logged_in` (`P_b`)**: Disassembled the original `x86_64` `steam.hdll` and reimplemented `SteamUser()->BLoggedOn()` in [`patches/hlsteam.patch`](patches/hlsteam.patch) (`native/common.cpp`), built against Steamworks SDK 1.64 (`arm64` `libsteam_api.dylib`).

## License

This project (the build scripts, patches and documentation in this repository) is licensed under the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE).

The pre-built binaries in the release archives are dynamically linked against the third-party libraries listed below, each distributed under its own license. Dead Cells itself, its assets (`hlboot.dat`, `res.pak`) and the Steamworks SDK are **not** part of this project or its license. Vendored upstream sources under `libsrc/` (HashLink `libs/sdl`) keep their original MIT / zlib licenses.

## Third-Party Licenses

Pre-built releases bundle unmodified or minimally patched builds of the following open-source libraries:

- **HashLink** — MIT License
- **SDL2 / SDL3 (`sdl2-compat`)** — zlib License
- **OpenAL Soft** — LGPL-2.0-or-later
- **mbedTLS** — Apache-2.0 OR GPL-2.0-or-later
- **libuv** — MIT License
- **libpng** — libpng License
- **libjpeg-turbo** — IJG / Modified BSD / zlib Licenses
- **libogg / libvorbis** — BSD-3-Clause License

**Valve Steamworks SDK (`libsteam_api.dylib`)** is proprietary software owned by Valve Corporation and is not included in this repository.
