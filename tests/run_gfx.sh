#!/bin/bash
# The tests only the raylib build can run: the ui module for real (no display needed), then the frame loops
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
## The tests that need a frame loop, hence a window: they run under Xvfb and end with graphics.quit().
if command -v xvfb-run >/dev/null 2>&1; then
    for f in tests/gfx_ui_draw_test.ol tests/gfx_image_test.ol; do
        out=$(timeout 60 bash tools/run-headless.sh "$f" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "OK   $f (Xvfb)"
        else
            echo "FAIL $f (Xvfb, exit $rc)"
            echo "$out" | grep -v "^INFO\|^WARNING" | tail -3 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    done
fi
[ $fails -eq 0 ]
