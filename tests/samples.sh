#!/bin/bash
# Runs the tests of the SAMPLES: every `*_test.ol` under docs/samples/, each next to the script it checks, in
# parallel. They are found, not listed — adding a test is adding the file; `<name>_testlib.ol` holds what
# several tests share (docs/samples/lib/ when several directories do). tests/check_samples.sh (in run.sh)
# keeps each test attached to a script of its directory and each helper used; the web app never loads them.
# The suffix `_test.ol` means this only UNDER docs/samples/: the files of tests/ named so are fixtures.
#
# Usage: bash tests/samples.sh                       all of them
#        bash tests/samples.sh docs/samples/sudoku docs/samples/foo_test.ol      a directory, or test files
#        bash tests/samples.sh --affected PATH...    the tests a change to these files can break: all of them
#            when the engine, the build, this runner or docs/samples/lib/ changed; those of the directory for a
#            sample in a folder; <name>_test.ol for a flat sample <name>.ol; none otherwise (the pre-commit hook)
# (the ./build/ollin binary must be compiled)
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
. tests/lib.sh
require_binary

if [ "${1:-}" = "--affected" ]; then
    shift
    all=0
    scope=""
    for f in "$@"; do
        case "$f" in
            docs/samples/lib/*|src/*|libs/*|CMakeLists.txt|tests/samples.sh|tests/lib.sh) all=1 ;;
            docs/samples/*/*) scope="$scope ${f%/*}" ;;
            docs/samples/*.ol)
                stem=${f%.ol}
                scope="$scope ${stem%_test}_test.ol" ;;
        esac
    done
    if [ "$all" = 1 ]; then
        set -- docs/samples
    else
        set --
        for target in $scope; do
            if [ -d "$target" ] || [ -f "$target" ]; then
                set -- "$@" "$target"
            fi
        done
        if [ $# -eq 0 ]; then
            echo "no sample test is affected"
            exit 0
        fi
    fi
fi

if [ $# -eq 0 ]; then
    set -- docs/samples
fi
for target in "$@"; do
    if [ ! -d "$target" ] && [ ! -f "$target" ]; then
        echo "error: $target is neither a directory nor a file"
        exit 2
    fi
done
tests=$(for target in "$@"; do
    if [ -d "$target" ]; then
        find "$target" -name '*_test.ol'
    else
        echo "$target"
    fi
done | sort -u)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export OLLIN tmp
jobs=$(nproc 2>/dev/null || echo 4)
printf '%s\n' $tests | xargs -P "$jobs" -n1 bash -c '. tests/lib.sh; k=${0//\//_}; run_pass "$0" >"$tmp/$k.out" 2>&1; echo $? >"$tmp/$k.rc"'

fails=0
count=0
echo "── sample tests ──────────────────────────────────"
for f in $tests; do
    count=$((count + 1))
    k=${f//\//_}
    cat "$tmp/$k.out"
    if [ "$(cat "$tmp/$k.rc")" != 0 ]; then
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
