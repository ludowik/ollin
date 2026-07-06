#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# ── Resynchronise le dépôt sur le dernier origin/main ───────────────────────
# Le conteneur distant est éphémère : à chaque reprise il repart d'un snapshot
# figé au commit de départ, PAS du HEAD distant courant. Sans resync, HEAD est
# périmé et committer par-dessus créerait une divergence. C'est sûr ici : le
# conteneur est jetable et tout le travail validé est poussé sur origin. On
# n'écrase JAMAIS de modifications locales non commitées (garde `status`).
if [ -d "$CLAUDE_PROJECT_DIR/.git" ]; then
  BR="main"
  if git -C "$CLAUDE_PROJECT_DIR" fetch origin "$BR" --quiet 2>/dev/null; then
    if [ -z "$(git -C "$CLAUDE_PROJECT_DIR" status --porcelain)" ]; then
      git -C "$CLAUDE_PROJECT_DIR" checkout -q "$BR" 2>/dev/null || true
      if git -C "$CLAUDE_PROJECT_DIR" reset --hard "origin/$BR" --quiet 2>/dev/null; then
        echo "Resynchronisé sur origin/$BR ($(git -C "$CLAUDE_PROJECT_DIR" rev-parse --short HEAD))"
      fi
    else
      echo "⚠ Modifications locales non commitées — resync ignorée (aucun écrasement)."
    fi
  else
    echo "⚠ git fetch impossible (réseau) — HEAD peut être périmé, resynchroniser manuellement."
  fi
fi

# Install missing Raylib system dependencies on Linux
# (most are pre-installed in the remote image)
if [ "$(uname)" = "Linux" ]; then
  sudo apt-get update -y -qq --ignore-missing 2>/dev/null || true
  sudo apt-get install -y -qq --no-install-recommends \
    build-essential cmake git python3 \
    libasound2-dev libx11-dev libxrandr-dev libxi-dev \
    libxcursor-dev libxinerama-dev 2>/dev/null || true

  # Install Emscripten SDK
  EMSDK_DIR="$HOME/emsdk"
  if [ ! -d "$EMSDK_DIR" ]; then
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
  fi
  "$EMSDK_DIR/emsdk" install latest
  "$EMSDK_DIR/emsdk" activate latest
  # shellcheck disable=SC1091
  source "$EMSDK_DIR/emsdk_env.sh"
  grep -qxF "source $EMSDK_DIR/emsdk_env.sh" ~/.bashrc \
    || echo "source $EMSDK_DIR/emsdk_env.sh" >> ~/.bashrc

  # Install Playwright for wasm/web testing
  if ! command -v node &>/dev/null; then
    sudo apt-get install -y -qq --no-install-recommends nodejs npm 2>/dev/null || true
  fi
  npm install -g @playwright/test 2>/dev/null || true
  npx playwright install --with-deps chromium 2>/dev/null || true
fi

# Configure + build (Raylib fetched automatically via FetchContent)
cmake -S "$CLAUDE_PROJECT_DIR" -B "$CLAUDE_PROJECT_DIR/build" \
      -DCMAKE_BUILD_TYPE=Release -Wno-dev --log-level=WARNING
cmake --build "$CLAUDE_PROJECT_DIR/build" -j"$(nproc)"
