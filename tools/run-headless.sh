#!/bin/bash
# Runs a .ol script with the native-raylib binary under a virtual display (Xvfb), which allows
# the graphics to be tested with no screen and captured through graphics.screenshot("file.png")
# (a path relative to the working directory).
#
# Usage:         bash tools/run-headless.sh <script.ol> [args...]
# Prerequisites: bash tools/native-gfx.sh (build-gfx/ollin), and Xvfb installed.
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
