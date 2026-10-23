#!/bin/bash
# UNIT-TEST guard: builds and runs tests/unit/*.cpp, the C++ checks of the units a script cannot exercise on
# its own (the path rules, the source registry). It builds in the directory of the binary under test, so the
# coverage build (OLLIN=build-cov/ollin) compiles them with the same instrumentation and tools/coverage.sh
# counts what they run.
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
build=$(dirname "$OLLIN")

log=$(mktemp)
trap 'rm -f "$log"' EXIT
if ! cmake --build "$build" --target unit_tests >"$log" 2>&1; then
    echo "FAIL the unit tests do not build"
    tail -15 "$log"
    exit 1
fi
out=$("$build/unit_tests" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK   $out"
else
    echo "FAIL unit tests"
    echo "$out"
    exit 1
fi
