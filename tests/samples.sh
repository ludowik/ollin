#!/bin/bash
# Runs the tests of the SAMPLES: every `*_test.ol` under docs/samples/, each next to the script it checks.
# They are found, not listed — adding a test is adding the file. tests/check_samples.sh (in run.sh) keeps each
# one attached to a script of its directory; the web app never loads them.
#
# Usage: bash tests/samples.sh                 all of them
#        bash tests/samples.sh docs/samples/sudoku docs/samples/foo_test.ol    a directory, or test files
# (the ./build/ollin binary must be compiled)
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

if [ ! -x "$OLLIN" ]; then
    echo "error: $OLLIN not found — compile it first (cmake --build build --target ollin)"
    exit 2
fi

if [ $# -eq 0 ]; then
    set -- docs/samples
fi
tests=$(for target in "$@"; do
    if [ -d "$target" ]; then
        find "$target" -name '*_test.ol'
    elif [ -f "$target" ]; then
        echo "$target"
    fi
done | sort -u)

fails=0
count=0
echo "── sample tests ──────────────────────────────────"
for f in $tests; do
    count=$((count + 1))
    out=$("$OLLIN" "$f" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
        echo "OK   $f"
    else
        echo "FAIL $f (exit $rc)"
        echo "$out" | tail -3 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
done
echo "──────────────────────────────────────────────────"
if [ $fails -eq 0 ]; then
    echo "SAMPLES GREEN ($count tests)"
    exit 0
fi
echo "$fails sample test(s) failed"
exit 1
