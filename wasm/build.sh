#!/bin/bash
set -e
cd "$(dirname "$0")/.."
emcmake cmake -S . -B build_wasm -DCMAKE_BUILD_TYPE=Release
cmake --build build_wasm
echo "Output: build_wasm/ollin.js + build_wasm/ollin.wasm"
