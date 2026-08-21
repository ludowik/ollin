#!/bin/bash
# Native build WITH raylib (graphics) for the headless tests (raylib desktop plus Xvfb).
# It reuses the raylib source the WASM build already fetched (FetchContent), so as NOT to
# clone from github, which the proxy policy blocks, nor to vendor raylib.
#
# Usage:   bash tools/native-gfx.sh
# Output:  build-gfx/ollin   (run it through tools/run-headless.sh)
set -e
cd "$(dirname "$0")/.."

# 1) Find a cached raylib source, created by a WASM or native-raylib build.
RAYSRC=""
for d in build-gfx/_deps/raylib-src build_wasm/_deps/raylib-src build/_deps/raylib-src; do
    if [ -f "$d/src/raylib.h" ]; then
        RAYSRC="$(pwd)/$d"
        break
    fi
done

if [ -z "$RAYSRC" ]; then
    echo "Source raylib introuvable en cache."
    echo "→ Lance d'abord le build WASM (bash tools/build-wasm.sh) : il récupère raylib"
    echo "  dans build_wasm/_deps/raylib-src, réutilisé ici."
    echo "  (github étant bloqué par le proxy, on ne peut pas cloner raylib à la volée.)"
    exit 1
fi
echo "raylib source : $RAYSRC"

# 2) Configure and build the native target with raylib, reusing that source.
EXTRA=""
[ -f build-gfx/_deps/raylib-src/src/raylib.h ] || EXTRA="-DFETCHCONTENT_SOURCE_DIR_RAYLIB=$RAYSRC"
cmake -S . -B build-gfx -DCMAKE_BUILD_TYPE=Release -DOLLIN_NATIVE_RAYLIB=ON $EXTRA
cmake --build build-gfx --target ollin -j"$(nproc)"
echo "OK → build-gfx/ollin"
