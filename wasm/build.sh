#!/bin/bash
set -e
cd "$(dirname "$0")/.."
emcmake cmake -S . -B build_wasm -DCMAKE_BUILD_TYPE=Release
cmake --build build_wasm
mkdir -p docs/wasm
cp build_wasm/ollin.js   docs/wasm/ollin.js
cp build_wasm/ollin.wasm docs/wasm/ollin.wasm
echo "Output: docs/wasm/ollin.js + docs/wasm/ollin.wasm"
