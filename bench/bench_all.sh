#!/usr/bin/env bash
# Run all 5 benchmarks for Ollin, Lua 5.5, and Python 3.
# Usage: bash bench/bench_all.sh  (from repo root)

set -euo pipefail
OLLIN=./build/ollin.exe
LUA=$(command -v lua5.4 2>/dev/null || command -v lua54 2>/dev/null || { [ -x "/c/Tools/lua/lua55.exe" ] && echo "/c/Tools/lua/lua55.exe"; } || command -v lua 2>/dev/null || echo "")
PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
DIR=$(dirname "$0")

# Extract the number after "time: " and before "s"
extract_time() {
    echo "$1" | grep -oE 'time: [0-9]+\.[0-9]+' | sed 's/time: //'
}

benchmarks=(fib loop objects array calls)

echo ""
echo "┌──────────────────────┬──────────────┬──────────────┬──────────────┐"
echo "│ Benchmark            │    Ollin     │    Lua 5.5   │   Python 3   │"
echo "├──────────────────────┼──────────────┼──────────────┼──────────────┤"

declare -A ollin_times lua_times py_times

for b in "${benchmarks[@]}"; do
    # Ollin
    if [ -x "$OLLIN" ]; then
        out=$("$OLLIN" "$DIR/bench_${b}.ol" 2>/dev/null)
        ollin_times[$b]=$(extract_time "$out")
    else
        ollin_times[$b]="N/A"
    fi
    # Lua
    if [ -n "$LUA" ] && [ -f "$DIR/bench_${b}.lua" ]; then
        out=$("$LUA" "$DIR/bench_${b}.lua" 2>/dev/null)
        lua_times[$b]=$(extract_time "$out")
    else
        lua_times[$b]="N/A"
    fi
    # Python
    if [ -n "$PY" ] && [ -f "$DIR/bench_${b}.py" ]; then
        out=$("$PY" "$DIR/bench_${b}.py" 2>/dev/null)
        py_times[$b]=$(extract_time "$out")
    else
        py_times[$b]="N/A"
    fi
done

labels=("fib(35) récursif" "boucle 10M" "map 100K" "array 1M" "appels 1M")
i=0
for b in "${benchmarks[@]}"; do
    label="${labels[$i]}"
    printf "│ %-20s │ %12s │ %12s │ %12s │\n" \
        "$label" \
        "${ollin_times[$b]:+${ollin_times[$b]}s}" \
        "${lua_times[$b]:+${lua_times[$b]}s}" \
        "${py_times[$b]:+${py_times[$b]}s}"
    i=$((i+1))
done

echo "└──────────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""
