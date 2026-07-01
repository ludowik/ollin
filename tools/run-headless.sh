#!/bin/bash
# Exécute un script .ol avec le binaire natif-raylib sous un affichage virtuel
# (Xvfb) — permet de tester le graphique sans écran, et de capturer via
# graphics.screenshot("fichier.png") (chemin relatif au CWD).
#
# Usage :  bash tools/run-headless.sh <script.ol> [args...]
# Prérequis : bash tools/native-gfx.sh (build-gfx/ollin) + Xvfb installé.
set -e
cd "$(dirname "$0")/.."

BIN=build-gfx/ollin
if [ ! -x "$BIN" ]; then
    echo "build-gfx/ollin absent — lance d'abord : bash tools/native-gfx.sh"
    exit 1
fi
if [ $# -lt 1 ]; then
    echo "Usage: bash tools/run-headless.sh <script.ol> [args...]"
    exit 1
fi

exec xvfb-run -a -s "-screen 0 1280x800x24" "$BIN" "$@"
