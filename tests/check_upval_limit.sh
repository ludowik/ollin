#!/bin/bash
# UPVALUE-CEILING guard: a function can capture as many variables as the field that names them can count.
# Past it the compiler refuses, and the message says so.
#
# The program is GENERATED: a function cannot hold the variables itself, since registers are bounded by
# the same width, so they are spread over two enclosing functions and read from the innermost one. Nothing
# about the ceiling is written down: a program far beyond any 16-bit ceiling is refused first, the ceiling is
# READ from the message, and a program just under it must then compile. The functions are never CALLED —
# running one would hit the VM's own 4096-register stack, a different ceiling.
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
fails=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

generate() {
    python3 - "$1" "$2" <<'PYEOF'
import sys
n = int(sys.argv[2])
out = ["func outer()"]
out += ["    var a%d = %d" % (i, i) for i in range(n)]
out.append("    func mid()")
out += ["        var b%d = %d" % (i, i) for i in range(n)]
out += ["        func inner()", "            var t = 0"]
out += ["            t = a%d" % i for i in range(n)]
out += ["            t = b%d" % i for i in range(n)]
out += ["            return t", "        end", "        return inner", "    end", "    return mid", "end",
        'print("compiled")']
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PYEOF
}

generate "$work/over.ol" 60000
ceiling=$("$OLLIN" "$work/over.ol" 2>&1 | sed -n 's/.*captures more than \([0-9][0-9]*\) upvalues.*/\1/p')
if [ -n "$ceiling" ]; then
    echo "OK   $((2 * 60000)) captured variables are refused, naming the ceiling ($ceiling)"
else
    echo "FAIL a function that captures $((2 * 60000)) variables is not refused"
    exit 1
fi

under=$((ceiling / 2 - 1))
generate "$work/under.ol" "$under"
if [ "$("$OLLIN" "$work/under.ol" 2>&1)" = "compiled" ]; then
    echo "OK   $((2 * under)) captured variables compile"
else
    echo "FAIL a function that captures $((2 * under)) variables, under the ceiling, is refused"
    fails=1
fi
exit $fails
