#!/bin/bash
# Runs the WHOLE Ollin test suite in one command:
#   - the "pass" suites (.ol files that must run without error, with asserts)
#   - the error suite (the compiler's rejection messages)
#   - the guards: the API's naming, and the grammar's coverage by syntax.ol
# Usage: bash tests/run.sh   (the ./build/ollin binary must be compiled)
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

if [ ! -x "$OLLIN" ]; then
    echo "error: $OLLIN not found — compile it first (cmake --build build --target ollin)"
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

echo "── pass suites (.ol) ─────────────────────────────"
run_pass tests/syntax.ol
run_pass tests/regressions.ol

echo "── error suite ───────────────────────────────────"
if ! bash tests/test_errors.sh; then
    fails=$((fails + 1))
fi

echo "── guard: API naming ─────────────────────────────"
if ! bash tests/check_naming.sh; then
    fails=$((fails + 1))
fi

echo "── guard: grammar coverage ───────────────────────"
if ! bash tests/check_grammar_coverage.sh; then
    fails=$((fails + 1))
fi

echo "── guard: markup nesting ─────────────────────────"
if ! bash tests/check_html.sh; then
    fails=$((fails + 1))
fi

echo "──────────────────────────────────────────────────"
if [ $fails -eq 0 ]; then
    echo "ALL GREEN"
    exit 0
fi
echo "$fails suite(s) failed"
exit 1
