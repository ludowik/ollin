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

# ── Hook git pre-commit : tests obligatoires avant chaque commit ─────────────
# Les hooks vivent dans .git/hooks, qui n'est pas versionné et disparaît donc à
# chaque conteneur neuf. Les nôtres sont dans tools/git-hooks/ (versionnés) et
# branchés ici par core.hooksPath — la règle « run.sh avant chaque commit » est
# ainsi tenue par git, pas par la mémoire.
if [ -d "$CLAUDE_PROJECT_DIR/tools/git-hooks" ]; then
  chmod +x "$CLAUDE_PROJECT_DIR"/tools/git-hooks/* 2>/dev/null || true
  git -C "$CLAUDE_PROJECT_DIR" config core.hooksPath tools/git-hooks 2>/dev/null \
    && echo "hook git pre-commit actif (tests avant chaque commit)"
fi

# ── Dépendances système (la plupart sont déjà dans l'image) ──────────────────
if [ "$(uname)" = "Linux" ]; then
  sudo apt-get update -y -qq --ignore-missing 2>/dev/null || true
  sudo apt-get install -y -qq --no-install-recommends \
    build-essential cmake git \
    libasound2-dev libx11-dev libxrandr-dev libxi-dev \
    libxcursor-dev libxinerama-dev 2>/dev/null || true

  # ── Interpréteurs de comparaison des benchmarks (bench/bench_all.sh) ───────
  # Lua est la RÉFÉRENCE du tableau et Python la troisième colonne : sans eux, le
  # benchmark n'a plus de point de comparaison. On installe la version la plus RÉCENTE
  # offerte par les dépôts, jamais un numéro en dur — il vieillirait en silence et le
  # jour où la distribution avance, on continuerait de mesurer l'ancienne.
  # Les candidats sont essayés du plus récent au plus ancien : les métadonnées d'un PPA
  # inaccessible (403 du proxy) annoncent des paquets qui ne s'installent pas.
  installer_le_plus_recent() {
    local motif="$1" p
    for p in $(apt-cache search --names-only "$motif" 2>/dev/null | awk '{print $1}' | sort -Vr); do
      if command -v "$p" >/dev/null 2>&1; then
        echo "$p"
        return 0
      fi
      if sudo apt-get install -y -qq --no-install-recommends "$p" >/dev/null 2>&1; then
        echo "$p"
        return 0
      fi
    done
    return 1
  }
  LUA_BIN=$(installer_le_plus_recent '^lua5\.[0-9]+$' || echo "")
  PY_BIN=$(installer_le_plus_recent '^python3\.[0-9]+$' || echo "")

  # Les versions retenues sont ÉCRITES ici : c'est ce hook qui les installe, donc il est
  # le seul à les connaître de source sûre. `bench_all.sh` les lit au lieu de fouiller le
  # PATH avec des motifs de noms — heuristique qui attrapait `python3.13-config`.
  # Fichier dans build/, gitignoré : c'est un état d'environnement, pas du code.
  mkdir -p "$CLAUDE_PROJECT_DIR/build"
  {
      echo "# Interpréteurs installés par .claude/hooks/session-start.sh — ne pas éditer."
      echo "LUA=${LUA_BIN}"
      echo "PY=${PY_BIN}"
  } > "$CLAUDE_PROJECT_DIR/build/bench-interpreters.env"
  echo "benchmarks : ${LUA_BIN:-lua absent} · ${PY_BIN:-python absent}"

  # ── SDK Emscripten (cible WASM) ────────────────────────────────────────────
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

  # ── Playwright + chromium (tests web/WASM) ─────────────────────────────────
  # `--with-deps` échoue ici (le proxy refuse les PPA) : le paquet npm et le
  # navigateur, eux, s'installent. Ne pas conclure que Playwright est absent.
  if ! command -v node &>/dev/null; then
    sudo apt-get install -y -qq --no-install-recommends nodejs npm 2>/dev/null || true
  fi
  npm install -g @playwright/test 2>/dev/null || true
  npx playwright install --with-deps chromium 2>/dev/null || true
fi

# ── Configuration + build natif (raylib via FetchContent) ───────────────────
cmake -S "$CLAUDE_PROJECT_DIR" -B "$CLAUDE_PROJECT_DIR/build" \
      -DCMAKE_BUILD_TYPE=Release -Wno-dev --log-level=WARNING
cmake --build "$CLAUDE_PROJECT_DIR/build" -j"$(nproc)"

# ── Chaînes de test graphique (mémo — voir CLAUDE.md « Tests graphiques ») ───
# DEUX moyens FONCTIONNENT ici ; ne jamais conclure « environnement cassé » :
#  A. Desktop raylib sous Xvfb : `bash tools/run-headless.sh <script.ol>`
#     (build-gfx/ollin ; capture via graphics.screenshot("f.png") CHEMIN RELATIF,
#      quitter avec graphics.quit() après la capture).
#  B. Playwright/chromium (/opt/pw-browsers/.../chrome) : file://PNG ou playground
#     servi en local — inspection pixels par drawImage+getImageData.
# build-gfx/ est gitignoré (perdu à chaque reprise du conteneur) → on le
# reconstruit pour que la chaîne A soit prête. Lancé en TÂCHE DE FOND détachée
# (nohup) pour ne pas rallonger le démarrage : la compilation (~1 min) se fait
# pendant le travail. Marqueur `build-gfx/.ready` écrit à la fin (source raylib
# réutilisée du build WASM ci-dessus). Voir CLAUDE.md : avant un test xvfb,
# vérifier build-gfx/ollin ; sinon lancer `bash tools/native-gfx.sh` (fallback).
nohup bash -c 'bash "'"$CLAUDE_PROJECT_DIR"'/tools/native-gfx.sh" >/tmp/native-gfx.log 2>&1 \
  && touch "'"$CLAUDE_PROJECT_DIR"'/build-gfx/.ready"' >/dev/null 2>&1 &
disown 2>/dev/null || true
echo "build-gfx : compilation raylib desktop en tâche de fond (tests xvfb) — log /tmp/native-gfx.log"
