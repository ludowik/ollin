#!/bin/bash
# The tests only the raylib build can run: the ui module for real (no display needed), then a frame loop
# under Xvfb. Run by tests/run.sh, and by tools/coverage.sh with the instrumented build.
# Usage: bash tests/run_gfx.sh   (OLLIN_GFX names the binary, build-gfx/ollin by default)
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
. tests/lib.sh

OLLIN=${OLLIN_GFX:-build-gfx/ollin}
export OLLIN_GFX=$OLLIN
fails=0

run_pass tests/gfx_ui_test.ol || fails=$((fails + 1))
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
[ $fails -eq 0 ]
