#!/bin/bash
# CONSTANT-OPERAND guard: past the last constant the instruction field can name, a literal falls back to
# LOAD_K and the generic opcode (ADDK and its siblings read their right operand from the pool, C being its
# index, and C is a 16-bit field).
#
# The program is GENERATED, and nothing about the ceiling is written down but the field's width: 70 000
# distinct constants first, then the operations whose constants land beyond it.
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2
fails=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$work/p.ol" <<'PYEOF'
import sys
out = ["var a = []"]
for i in range(70000):
    out.append("a.push(%d.5)" % i)
out += [
    "var n = 7",
    "assert(n + 123456789 == 123456796)",
    "assert(n - 123456789 == -123456782)",
    "assert(n * 123456789 == 864197523)",
    "assert(n < 99999999 and n <= 99999999 and not (n > 99999999) and not (n >= 99999999))",
    "assert(n <> 123456789 and not (n == 123456789))",
    'assert("x" + "far away" == "xfar away")',
    "n += 123456789",
    "assert(n == 123456796 and len(a) == 70000)",
    'print("pool overflow ok")',
]
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PYEOF
if [ "$("$OLLIN" "$work/p.ol" 2>&1)" = "pool overflow ok" ]; then
    echo "OK   constants beyond the field fall back to LOAD_K"
else
    echo "FAIL a constant past the last index of the field is wrong"
    fails=1
fi
exit $fails
