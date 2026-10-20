#!/bin/bash
# Runs the WHOLE Ollin test suite in one command:
#   - the "pass" suites (.ol files that must run without error, with asserts)
#   - the error suite (the compiler's rejection messages)
#   - the guards: the API's naming, and the grammar's coverage by syntax.ol, the catalogue of samples, the generated programs
# The tests of the SAMPLES sit next to their script and run apart, by tests/samples.sh.
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

# Modules the headless build only stubs (ui) are exercised by the raylib build when it exists. It is
# rebuilt first — incremental, so cheap — since nothing else keeps build-gfx/ollin up to date, and a
# stale binary would pass or fail for the wrong reason.
if [ -x build-gfx/ollin ]; then
    echo "── pass suites (.ol, raylib build) ───────────────"
    if bash tools/native-gfx.sh >/dev/null 2>&1; then
        OLLIN=build-gfx/ollin run_pass tests/gfx_ui_test.ol
        if command -v xvfb-run >/dev/null 2>&1; then
            out=$(timeout 60 bash tools/run-headless.sh tests/gfx_ui_draw_test.ol 2>&1)
            rc=$?
            if [ $rc -eq 0 ]; then
                echo "OK   tests/gfx_ui_draw_test.ol (Xvfb)"
            else
                echo "FAIL tests/gfx_ui_draw_test.ol (Xvfb, exit $rc)"
                echo "$out" | grep -v "^INFO\|^WARNING" | tail -3 | sed 's/^/     /'
                fails=$((fails + 1))
            fi
        fi
    else
        echo "FAIL build-gfx (tools/native-gfx.sh did not build)"
        fails=$((fails + 1))
    fi
fi

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

echo "── guard: function ceiling ───────────────────────"
if ! bash tests/check_func_limit.sh; then
    fails=$((fails + 1))
fi

echo "── guard: sample catalogue ───────────────────────"
if ! bash tests/check_samples.sh; then
    fails=$((fails + 1))
fi

echo "── guard: trace animations ────────────────────────"
if ! bash tests/check_trace_source.sh; then
    fails=$((fails + 1))
fi

echo "── guard: constant operands ──────────────────────"
if ! bash tests/check_const_operands.sh; then
    fails=$((fails + 1))
fi

echo "──────────────────────────────────────────────────"
if [ $fails -eq 0 ]; then
    echo "ALL GREEN"
    exit 0
fi
echo "$fails suite(s) failed"
exit 1
