#!/bin/bash
# CLASS-NAME guard: the name of a class is an id of a registry (src/collections/map.cpp) that holds a 16-bit number,
# so a program can have a limited number of DIFFERENT class names. Past it the declaration is refused with a message
# that names the ceiling, and under it every class must be declared. The program is GENERATED, as the ceiling itself
# forbids committing one, and the number is read from the message so that the guard survives the day it moves.
# (The native classes — Color, Quat, Camera… — take some names before the program's own.)
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

generate() {
    python3 - "$1" "$2" <<'PYEOF'
import sys
n = int(sys.argv[2])
out = ["class C%d\nend" % i for i in range(n)]
out.append('print("compiled")')
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PYEOF
}

generate "$work/over.ol" 70000
ceiling=$("$OLLIN" "$work/over.ol" 2>&1 | sed -n 's/.*too many different class names (max \([0-9][0-9]*\)).*/\1/p')
if [ -n "$ceiling" ]; then
    echo "OK   70000 class names are refused, naming the ceiling ($ceiling)"
else
    echo "FAIL a program with 70000 different class names is not refused"
    exit 1
fi

under=$((ceiling - 100))
generate "$work/under.ol" "$under"
if [ "$("$OLLIN" "$work/under.ol" 2>&1)" = "compiled" ]; then
    echo "OK   $under class names, under the ceiling, are all declared"
else
    echo "FAIL a program with $under different class names, under the ceiling, is refused"
    fails=1
fi
exit $fails
