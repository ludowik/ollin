#!/bin/bash
# Build natif AVEC raylib (graphique) pour les tests headless (raylib desktop + Xvfb).
# Réutilise la source raylib déjà récupérée par le build WASM (FetchContent), pour
# ne PAS re-cloner depuis github (bloqué par la politique proxy) ni vendoriser raylib.
#
# Usage :  bash tools/native-gfx.sh
# Produit : build-gfx/ollin   (exécuter via tools/run-headless.sh)
set -e
cd "$(dirname "$0")/.."

# 1) Trouver une source raylib en cache (créée par un build WASM ou natif-raylib).
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

# 2) Configurer + builder le natif avec raylib, en réutilisant cette source.
EXTRA=""
[ -f build-gfx/_deps/raylib-src/src/raylib.h ] || EXTRA="-DFETCHCONTENT_SOURCE_DIR_RAYLIB=$RAYSRC"
cmake -S . -B build-gfx -DCMAKE_BUILD_TYPE=Release -DOLLIN_NATIVE_RAYLIB=ON $EXTRA
cmake --build build-gfx --target ollin -j"$(nproc)"
echo "OK → build-gfx/ollin"
