#!/bin/bash
# Lance TOUTE la suite de tests Ollin en une commande :
#   - suites « pass » (.ol qui doivent s'exécuter sans erreur, avec asserts)
#   - suite d'erreurs (messages de rejet du compilateur)
# Usage : bash tests/run.sh   (le binaire ./build/ollin doit être compilé)
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

if [ ! -x "$OLLIN" ]; then
    echo "erreur : $OLLIN introuvable — compiler d'abord (cmake --build build --target ollin)"
    exit 2
fi

fails=0

run_pass() {
    local f="$1"
    local out
    out=$("$OLLIN" "$f" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "OK   $f"
    else
        echo "FAIL $f (exit $rc)"
        echo "$out" | tail -3 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
}

echo "── suites pass (.ol) ─────────────────────────────"
run_pass tests/syntax.ol
run_pass tests/regressions.ol

echo "── suite d'erreurs ───────────────────────────────"
if ! bash tests/test_errors.sh; then
    fails=$((fails + 1))
fi

echo "──────────────────────────────────────────────────"
if [ $fails -eq 0 ]; then
    echo "TOUT VERT"
    exit 0
fi
echo "$fails suite(s) en échec"
exit 1
