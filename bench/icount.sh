#!/usr/bin/env bash
# Counts the INSTRUCTIONS executed, so as to tell a real cost from an effect of code placement.
#
# Why this tool: bench_all.sh's times vary by about 7 % with the address the compiler gives the
# opcode handlers, which all live in the single run_goto function, dispatching by computed goto.
# A 4 % regression is therefore undetectable there, and "it is the code layout" becomes a claim
# that can be neither checked nor refuted. The number of instructions executed, on the other
# hand, depends neither on the code's address nor on the cache: it measures the WORK. There are
# two readings, and only one calls for a fix:
#
#   instructions up      a real cost: the engine does more work.
#   instructions steady  placement: there is nothing to optimise, and freezing a favourable
#                        layout would be pointless, the next commit undoing it.
#
# Usage:
#   bash bench/icount.sh                        counts for ./build/ollin
#   bash bench/icount.sh <git-ref>              compares ./build/ollin with that commit
#   bash bench/icount.sh <git-ref> <other-ref>  compares two commits with each other
#
# Sensitivity CHECKED: four comparisons added at the top of op_ADD, which the compiler cannot
# eliminate, come out at +0.61 % on fib — an overhead bench_all.sh's times would have drowned in
# their own noise. Beware when writing such a probe: contradictory tests
# (`v.is_range() && v.is_iterator()`) are removed at compile time and measure NOTHING, which
# would give the illusion of a blind tool.
#
# A commit passed as an argument is built in a throwaway worktree under /tmp, removed at the end.
# The scripts measured are SMALLER than those in bench/: callgrind slows execution about
# fiftyfold, and an instruction count needs no long series — being deterministic, one run is
# enough and gives the same figure every time.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

if ! command -v valgrind >/dev/null 2>&1; then
    echo "valgrind is missing: sudo apt-get install -y valgrind"
    exit 1
fi

work=$(mktemp -d)
scripts=""
# THIS run's worktrees carry the PID in their name, and the cleanup removes only those: a prefix
# shared by every run would let a second icount.sh, started in parallel, destroy the first one's
# binaries in mid-measurement. The name cannot come from a variable filled by build_ref, which is
# called inside a command substitution, hence in a subshell — a list accumulated there would
# never reach this cleanup, and a worktree was indeed left behind.
prefix="/tmp/icount-$$-"
cleanup() {
    local w
    for w in $(git worktree list --porcelain | sed -n "s|^worktree $prefix|$prefix|p"); do
        git worktree remove --force "$w" >/dev/null 2>&1
    done
    rm -rf "$work"
}
trap cleanup EXIT

# The three hot paths that stand apart: calls and conditional jumps (fib), a numeric arithmetic
# loop (loop), and maps with iteration (map).
mkdir -p "$work/scripts"
cat > "$work/scripts/fib.ol" <<'EOF'
func fib(n)
    if n <= 1 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end
print(fib(24))
EOF
cat > "$work/scripts/loop.ol" <<'EOF'
var s = 0
for i = 1, 300000 do
    s += i
end
print(s)
EOF
cat > "$work/scripts/map.ol" <<'EOF'
var m = {}
for i = 1, 20000 do
    m["k" + i] = i
end
var t = 0
for k, v in m do
    t += v
end
print(t)
EOF
scripts="fib loop map"

# Builds a git ref in a throwaway worktree and returns the path of the binary.
build_ref() {
    local ref="$1"
    local sha
    sha=$(git rev-parse --short "$ref" 2>/dev/null) || {
        echo "unknown git ref: $ref" >&2
        return 1
    }
    local dir="$prefix$sha"
    # An `rm -rf` alone would leave git's own record behind, should a run be interrupted before
    # the trap, and `git worktree add` would then refuse a path it already knows, with a message
    # that explains nothing. So we unregister first, then wipe what is left.
    git worktree remove --force "$dir" >/dev/null 2>&1
    rm -rf "$dir"
    git worktree prune >/dev/null 2>&1
    git worktree add -q "$dir" "$sha" || return 1
    cmake -S "$dir" -B "$dir/build" -DCMAKE_BUILD_TYPE=Release -Wno-dev --log-level=ERROR >/dev/null 2>&1
    cmake --build "$dir/build" -j"$(nproc 2>/dev/null || echo 4)" --target ollin >/dev/null 2>&1 || {
        echo "cannot build $ref" >&2
        return 1
    }
    echo "$dir/build/ollin"
}

# The number of instructions <binary> executes on <script>. Deterministic.
count_insns() {
    valgrind --tool=callgrind --callgrind-out-file=/dev/null "$1" "$2" 2>&1 \
        | grep -oE "refs: *[0-9,]+" | tr -d ' ,' | sed 's/refs://'
}

current=$([ -x "./build/ollin" ] && echo "./build/ollin" || echo "./build/ollin.exe")
if [ $# -ge 2 ]; then
    name_a="$1"
    name_b="$2"
    bin_a=$(build_ref "$1") || exit 1
    bin_b=$(build_ref "$2") || exit 1
elif [ $# -eq 1 ]; then
    name_a="$1"
    name_b="build/ollin"
    bin_a=$(build_ref "$1") || exit 1
    bin_b="$current"
else
    name_a=""
    name_b="build/ollin"
    bin_b="$current"
fi

echo ""
if [ -z "$name_a" ]; then
    printf "  instructions executed — %s\n\n" "$name_b"
    printf "  %-8s %16s\n" "script" "instructions"
    for s in $scripts; do
        printf "  %-8s %16s\n" "$s" "$(count_insns "$bin_b" "$work/scripts/$s.ol")"
    done
    echo ""
    exit 0
fi

printf "  instructions executed — %s to %s\n" "$name_a" "$name_b"
printf "  (up means a real cost; steady means code placement, and nothing to optimise)\n\n"
printf "  %-8s %16s %16s %10s\n" "script" "$name_a" "$name_b" "delta"
for s in $scripts; do
    a=$(count_insns "$bin_a" "$work/scripts/$s.ol")
    b=$(count_insns "$bin_b" "$work/scripts/$s.ol")
    if [ -z "$a" ] || [ -z "$b" ]; then
        printf "  %-8s %16s %16s %10s\n" "$s" "${a:-N/A}" "${b:-N/A}" "N/A"
        continue
    fi
    awk -v s="$s" -v a="$a" -v b="$b" 'BEGIN { printf "  %-8s %16d %16d %+9.2f%%\n", s, a, b, (b - a) / a * 100 }'
done
echo ""
