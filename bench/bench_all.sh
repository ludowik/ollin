#!/usr/bin/env bash
# Run all 5 benchmarks for Ollin, Lua 5.5, and Python 3.
# Usage: bash bench/bench_all.sh  (from repo root)

set -euo pipefail
OLLIN=$([ -x "./build/ollin" ] && echo "./build/ollin" || echo "./build/ollin.exe")
LUA=$(command -v lua5.4 2>/dev/null || command -v lua54 2>/dev/null || { [ -x "/c/Tools/lua/lua55.exe" ] && echo "/c/Tools/lua/lua55.exe"; } || command -v lua 2>/dev/null || echo "")
PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
DIR=$(dirname "$0")

extract_time() {
    echo "$1" | grep -oE 'time: [0-9]+\.[0-9]+' | sed 's/time: //'
}

benchmarks=(fib loop objects array calls)
labels=("fib(35) récursif" "boucle 10M" "map 100K" "array 1M" "appels 1M")

echo ""
echo "┌──────────────────────┬──────────────┬──────────────┬──────────────┐"
echo "│ Benchmark            │   Lua 5.5    │    Ollin     │   Python 3   │"
echo "├──────────────────────┼──────────────┼──────────────┼──────────────┤"

ollin_times=()
lua_times=()
py_times=()

for b in "${benchmarks[@]}"; do
    if [ -x "$OLLIN" ]; then
        out=$("$OLLIN" "$DIR/bench_${b}.ol" 2>/dev/null)
        ollin_times+=("$(extract_time "$out")")
    else
        ollin_times+=("N/A")
    fi
    if [ -n "$LUA" ] && [ -f "$DIR/bench_${b}.lua" ]; then
        out=$("$LUA" "$DIR/bench_${b}.lua" 2>/dev/null)
        lua_times+=("$(extract_time "$out")")
    else
        lua_times+=("N/A")
    fi
    if [ -n "$PY" ] && [ -f "$DIR/bench_${b}.py" ]; then
        out=$("$PY" "$DIR/bench_${b}.py" 2>/dev/null)
        py_times+=("$(extract_time "$out")")
    else
        py_times+=("N/A")
    fi
done

ratio() {
    local val="$1" ref="$2"
    if [[ "$val" == "N/A" || "$ref" == "N/A" || "$ref" == "0" ]]; then
        echo "N/A"
    else
        awk "BEGIN { printf \"x%.2f\", $val / $ref }"
    fi
}

for i in 0 1 2 3 4; do
    label="${labels[$i]}"
    ot="${ollin_times[$i]}"
    lt="${lua_times[$i]}"
    pt="${py_times[$i]}"
    or=$(ratio "$ot" "$lt")
    pr=$(ratio "$pt" "$lt")
    printf "│ %-20s │ %12s │ %12s │ %12s │\n" \
        "$label" \
        "${lt:+${lt}s}" \
        "$or" \
        "$pr"
done

echo "└──────────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""
