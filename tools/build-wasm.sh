#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Source emsdk if not already active
if ! command -v emcc &>/dev/null; then
    EMSDK_WIN="C:/Tools/emsdk"
    EMSDK_UNIX=$(cygpath -u "$EMSDK_WIN" 2>/dev/null || echo "$EMSDK_WIN")
    source "$EMSDK_UNIX/emsdk_env.sh" --build=Release 2>/dev/null \
        || { echo "emcc not found — run: source C:/Tools/emsdk/emsdk_env.sh"; exit 1; }
fi

# Réutiliser un raylib déjà téléchargé (FetchContent) si présent — évite un clone
# github à chaque build et permet de builder hors-ligne / proxy restreint.
EXTRA=""
for d in build_wasm/_deps/raylib-src build/_deps/raylib-src; do
    if [ -f "$d/src/raylib.h" ]; then
        EXTRA="-DFETCHCONTENT_SOURCE_DIR_RAYLIB=$(pwd)/$d"
        break
    fi
done

emcmake cmake -S . -B build_wasm -DCMAKE_BUILD_TYPE=Release $EXTRA
cmake --build build_wasm
mkdir -p docs/wasm
cp build_wasm/ollin.js   docs/wasm/ollin.js
cp build_wasm/ollin.wasm docs/wasm/ollin.wasm
echo "Output: docs/wasm/ollin.js + docs/wasm/ollin.wasm"
