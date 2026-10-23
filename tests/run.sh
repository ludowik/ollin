#!/bin/bash
# Runs the WHOLE Ollin test suite in one command:
#   - the "pass" suites (.ol files that must run without error, with asserts)
#   - the error suite (the compiler's rejection messages)
#   - the guards: the API's naming and coverage, the persistence of `data`, the grammar's coverage by syntax.ol, the catalogue of samples, the generated programs
# The tests of the SAMPLES sit next to their script and run apart, by tests/samples.sh.
# Usage: bash tests/run.sh   (the ./build/ollin binary must be compiled)
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
. tests/lib.sh
require_binary

fails=0

echo "── pass suites (.ol) ─────────────────────────────"
run_pass tests/syntax.ol || fails=$((fails + 1))
for f in tests/regressions/*/*.ol; do
    run_pass "$f" || fails=$((fails + 1))
done

# Modules the headless build only stubs (ui) are exercised by the raylib build when it exists. It is
# rebuilt first — incremental, so cheap — since nothing else keeps build-gfx/ollin up to date, and a
# stale binary would pass or fail for the wrong reason.
if [ -x build-gfx/ollin ]; then
    echo "── pass suites (.ol, raylib build) ───────────────"
    if bash tools/native-gfx.sh >/dev/null 2>&1; then
        OLLIN=build-gfx/ollin run_pass tests/gfx_ui_test.ol || fails=$((fails + 1))
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

# The error suite and the guards are independent and read-only (the ones that write work in a directory of their
# own), so they run side by side; each report is printed whole, in this order.
checks=(
    "error suite|tests/test_errors.sh"
    "guard: API naming|tests/check_naming.sh"
    "guard: grammar coverage|tests/check_grammar_coverage.sh"
    "guard: API coverage|tests/check_api_coverage.sh"
    "guard: markup nesting|tests/check_html.sh"
    "guard: function ceiling|tests/check_func_limit.sh"
    "guard: sample catalogue|tests/check_samples.sh"
    "guard: trace animations|tests/check_trace_source.sh"
    "guard: constant operands|tests/check_const_operands.sh"
    "guard: upvalue ceiling|tests/check_upval_limit.sh"
    "guard: data persistence|tests/check_data_persistence.sh"
)
reports=$(mktemp -d)
trap 'rm -rf "$reports"' EXIT
for i in "${!checks[@]}"; do
    (bash "${checks[$i]#*|}" >"$reports/$i.out" 2>&1; echo $? >"$reports/$i.rc") &
done
wait
for i in "${!checks[@]}"; do
    title="${checks[$i]%%|*}"
    rule=""
    for ((k = ${#title}; k < 46; k++)); do
        rule="$rule─"
    done
    echo "── $title $rule"
    cat "$reports/$i.out"
    if [ "$(cat "$reports/$i.rc")" != 0 ]; then
        fails=$((fails + 1))
    fi
done

echo "──────────────────────────────────────────────────"
if [ $fails -eq 0 ]; then
    echo "ALL GREEN"
    exit 0
fi
echo "$fails suite(s) failed"
exit 1
