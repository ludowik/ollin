#!/bin/bash
# FUNCTION-CEILING guard: a program may declare as many functions as the engine says it can, and
# every one of them must be CALLABLE BY NAME — including the last.
#
# Why this guard exists: a named call is compiled to CALL_FUNC, which carries the callee's index
# in one instruction field. Widening that index was attempted twice and both times some site kept
# a narrower type, so a call past the 255th function returned the WRONG function's value in
# silence — `g299()` gave 43, which is 299 truncated to eight bits. No test could see it: the
# ceiling itself forbids writing 300 functions in a committed file, which is also what forced the
# six string checkers of regressions.ol to be merged into one.
#
# So the program is GENERATED here, and nothing about the ceiling is written down: the script
# searches for it, then checks both sides of it. It therefore keeps working the day the ceiling
# moves — the number comes from the engine, never from this file.
#
# ⚠ A loop creating closures does NOT exercise this: one `func` written in the source is ONE
# prototype, whatever the number of closures made from it at run time, and a closure held in a
# variable is called through CALL_DYN, whose index lives in a register and has no ceiling. The
# limit counts function BODIES in the text, and only a named call reaches CALL_FUNC.
set -u
OLLIN=${OLLIN:-./build/ollin}
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

# A program of n functions: each gi returns i, the sum exercises every one of them, and three
# named calls check individual values — the LAST one is the case that was silently wrong.
gen() {
    python3 - "$1" "$work/p.ol" <<'PYEOF'
import sys
n, path = int(sys.argv[1]), sys.argv[2]
out = []
for i in range(1, n + 1):
    out.append("func g%d()\n    return %d\nend\n" % (i, i))
out.append("var s = 0\n")
for i in range(1, n + 1):
    out.append("s += g%d()\n" % i)
out.append("print(s)\n")
out.append("print(g%d())\n" % n)          # the last index: the one a narrowing truncates
out.append("print(g%d())\n" % ((n // 2) + 1))
out.append("print(g1())\n")
open(path, "w").write("".join(out))
PYEOF
}

# Doubling then bisection, so that the program finally checked holds EXACTLY as many functions as
# the engine accepts: the last index is the one a narrowing truncates, and any smaller program
# would pass while being wrong. Capped, because the guard must stay fast the day the ceiling rises
# to tens of thousands — and there the program-size ceiling binds first anyway.
cap=4096
ok_n=0
bad_n=0
bad_msg=""

try_n() {
    gen "$1"
    if out=$("$OLLIN" "$work/p.ol" 2>&1); then
        ok_n=$1
        ok_out=$out
        return 0
    fi
    bad_n=$1
    bad_msg=$out
    return 1
}

n=64
while [ $n -le $cap ] && try_n "$n"; do
    n=$((n * 2))
done
if [ $bad_n -ne 0 ]; then
    while [ $((bad_n - ok_n)) -gt 1 ]; do
        try_n $(((ok_n + bad_n) / 2))
    done
fi

if [ $ok_n -eq 0 ]; then
    echo "FAIL function ceiling (even 64 functions are refused: $bad_msg)"
    exit 1
fi

# What the accepted program must print: the sum of 1..n, then the three named calls.
want=$(printf '%s\n%s\n%s\n%s' "$((ok_n * (ok_n + 1) / 2))" "$ok_n" "$((ok_n / 2 + 1))" "1")
if [ "$ok_out" = "$want" ]; then
    echo "OK   $ok_n functions declared and each one called by name"
else
    echo "FAIL $ok_n functions: a named call gave the wrong value"
    echo "     expected: $(echo "$want" | tr '\n' ' ')"
    echo "     got:      $(echo "$ok_out" | tr '\n' ' ')"
    fails=$((fails + 1))
fi

# The other side of the ceiling: refused, and refused by NAMING the limit. A program that is
# simply truncated instead would pass the check above while running the wrong code.
if [ $bad_n -eq 0 ]; then
    echo "OK   ceiling above $cap functions (search capped, nothing to refuse)"
elif echo "$bad_msg" | grep -q "too many functions (max "; then
    echo "OK   $bad_n functions refused: $(echo "$bad_msg" | head -1)"
else
    echo "FAIL $bad_n functions: expected a 'too many functions' refusal, got: $(echo "$bad_msg" | head -1)"
    fails=$((fails + 1))
fi

exit $((fails > 0))
