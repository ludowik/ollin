#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install missing Raylib system dependencies on Linux
# (most are pre-installed in the remote image)
if [ "$(uname)" = "Linux" ]; then
  sudo apt-get update -y -qq --ignore-missing 2>/dev/null || true
  sudo apt-get install -y -qq --no-install-recommends \
    build-essential cmake \
    libasound2-dev libx11-dev libxrandr-dev libxi-dev \
    libxcursor-dev libxinerama-dev 2>/dev/null || true
fi

# Configure + build (Raylib fetched automatically via FetchContent)
cmake -S "$CLAUDE_PROJECT_DIR" -B "$CLAUDE_PROJECT_DIR/build" \
      -DCMAKE_BUILD_TYPE=Release -Wno-dev --log-level=WARNING
cmake --build "$CLAUDE_PROJECT_DIR/build" -j"$(nproc)"
