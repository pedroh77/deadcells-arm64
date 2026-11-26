# Dead Cells — Native macOS ARM64 (Apple Silicon) Runtime

Rebuilds the **HashLink JIT VM (`hl` + `libhl`)** and all required native `.hdll` plugins (`fmt`, `openal`, `sdl`, `ssl`, `steam`, `ui`, `uv`) natively for `arm64` on macOS, running the unmodified Steam `hlboot.dat` (HashLink v4 bytecode) and `res.pak` without Rosetta 2.

## Why?

Even though Rosetta 2 generally performs well, Dead Cells on macOS has very noticeable frame drops and stutters on Apple Silicon that a 2D pixel-art platformer really shouldn't have.

The main reason seems to be how the game is built: Dead Cells doesn't ship as a native compiled game binary. The actual game logic and assets live in architecture-independent files (`hlboot.dat` HashLink bytecode and `res.pak`), while the `deadcells` executable is essentially an `x86_64` HashLink JIT VM plus native `.hdll` plugins. Under Rosetta 2, macOS ends up translating `x86_64` code generated on the fly by HashLink's JIT, which creates a noticeable bottleneck.

To get around this, we can build a native `arm64` runtime that runs the unmodified Steam `hlboot.dat` and `res.pak` directly on Apple Silicon without Rosetta 2.

## Results

| Metric | Original (`deadcells.real` x86_64 via Rosetta 2) | Native (`arm64/hl` Apple Silicon JIT) |
|---|---|---|
| Architecture | `x86_64` (Rosetta 2 translating JIT code) | `arm64` native (HashLink PR #932 `MAP_JIT` backend) |
| Native bindings matched | 503 / 503 | **503 / 503** (`ok=503 bad=0`) |
| 1,291 shaders load time | `1.891s` | **`0.515s` (~3.67x faster)** |
| Steam API / Cloud / Achievements | Working (`libsteam_api.dylib` x86_64) | **Working** (`libsteam_api.dylib` universal `arm64`, installed by `setup-steam-api.sh`) |
| Nintendo / Switch Pro layout fix | Optional | Optional (`SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0`) |

Tested on a MacBook Air M1 (8 GB) running macOS 27.2.1.

## Quick Install (Pre-built Release)

1. Download the latest release archive from GitHub Releases and extract it.
2. Run the installer from the extracted folder:

   ```bash
   cd ~/Downloads/deadcells-arm64-*
   ./install.sh
   ```

3. Launch Dead Cells from Steam.

The installer does everything in one go: it finds your Dead Cells folder (prompting for the path if it can't), copies the runtime into `arm64/`, keeps the original launcher as `deadcells.real`, installs the `deadcells` wrapper, clears the Gatekeeper quarantine and installs Valve's `libsteam_api.dylib` from a copy already on your machine.

The archive contains `install.sh` (one-shot installer), `arm64/` (the native runtime), `launcher` (wrapper installed as `deadcells`), `setup-steam-api.sh` (Steamworks dylib helper, used by the installer) and `LICENSE`.

Useful options:

| Option | Description |
|---|---|
| `--game-dir PATH` | Dead Cells folder, for non-default Steam libraries |
| `--steam-api-url URL` | download `libsteam_api.dylib` from a URL you trust, if no local copy is found |
| `--uninstall` | restore the original launcher and remove `arm64/` |

`libsteam_api.dylib` is proprietary and **not** bundled: it is not publicly downloadable (Valve ships it only inside the SDK, the Steam client and Steam games), so the installer prefers the copy in your Steam client app bundle or another ARM64 Steam game.

To revert, run `./install.sh --uninstall` (or delete `arm64/` and rename `deadcells.real` back to `deadcells`).

A Steam update to Dead Cells can restore the original `deadcells` launcher. If the game runs under Rosetta 2 again after an update, just rerun `./install.sh`; it is non-destructive.

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

# Install into the Dead Cells Steam folder (runs tools/install.sh)
make install

# Restore the original x86_64 launcher and remove arm64/
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
