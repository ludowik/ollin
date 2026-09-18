#!/usr/bin/env bash
# Run all benchmarks for Ollin, Lua, LuaJIT, Python 3, and Java.
# Usage: bash bench/bench_all.sh  (from repo root)
#        RUNS=5 bash bench/bench_all.sh   (override number of runs)
#        RAW=1 bash bench/bench_all.sh    (also print the absolute times, one line per benchmark)
#
# The table shows the reference's time and a MULTIPLE for the others, which is what one reads. But
# docs/data/bench-snapshot.json stores the TIMES, for the reference as for the others, so RAW=1
# prints them in a form a script can read: "RAW <id> <lua> <ollin> <python> <java> <luajit>",
# seconds, empty for a missing interpreter. Without it, publishing a reading meant editing this
# script and running the whole bench a SECOND time — two readings that differ by noise, so the
# report and the published file no longer agreed.
#
# Every benchmark runs RUNS times (3 by default) and the BEST time is kept: a single run is too
# sensitive to noise, through CPU and cache contention, and can show a skewed coefficient.

set -euo pipefail
# Table alignment: ${#label} must count CHARACTERS and not bytes, or an accented label comes out
# too short. With no UTF-8 locale available we simply fall back to that slight misalignment.
export LC_ALL=${LC_ALL:-C.UTF-8}
RUNS=${RUNS:-3}
OLLIN=$([ -x "./build/ollin" ] && echo "./build/ollin" || echo "./build/ollin.exe")
# The interpreters compared against, looked up in the PATH over an EXPLICIT list of names. No
# glob on binary names: `python3.[0-9]*` caught `python3.13-config`, which runs nothing, and the
# table came out empty.
first_present() {
    local name
    for name in "$@"; do
        if command -v "$name" >/dev/null 2>&1; then
            echo "$name"
            return 0
        fi
    done
    return 1
}
LUA=$(first_present lua5.4 lua5.3 lua54 lua || echo "")
[ -n "$LUA" ] || { [ -x "/c/Tools/lua/lua55.exe" ] && LUA="/c/Tools/lua/lua55.exe"; }
LUAJIT=$(first_present luajit || echo "")
PY=$(first_present python3 python || echo "")
JAVA=$(first_present java || echo "")
DIR=$(dirname "$0")

extract_time() {
    echo "$1" | grep -oE 'time: [0-9]+\.[0-9]+' | sed 's/time: //'
}

# best_of <interp> <script>: runs the script RUNS times and returns the best (smallest)
# time extracted, or "N/A" when no run produced a time.
best_of() {
    local interp="$1" script="$2"
    local best="" t
    for ((r = 0; r < RUNS; r++)); do
        t=$(extract_time "$("$interp" "$script" 2>/dev/null)")
        [ -z "$t" ] && continue
        if [ -z "$best" ] || awk "BEGIN { exit !($t < $best) }"; then
            best="$t"
        fi
    done
    echo "${best:-N/A}"
}

benchmarks=(fib loop objects array calls closures strings classes iter float)
labels=("fib(35) recursive" "loop 10M" "map 100K" "array 1M" "calls 1M" "closures 1M"
        "strings 200K" "classes 200K" "iter 2.4M" "mandelbrot 200x200")

echo ""
echo "  (best of $RUNS runs per benchmark)"
echo "┌──────────────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐"
# The version is READ from the interpreter, never written by hand: the header announced "Lua 5.5"
# whatever version was measured, which made the table wrong as soon as the container provided
# another one.
lua_label="Lua ?"
if [ -n "$LUA" ]; then
    lua_label="Lua $("$LUA" -v 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
fi
py_label="Python ?"
if [ -n "$PY" ]; then
    py_label="Python $("$PY" -V 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
fi
# `java -version` can be preceded by a "Picked up JAVA_TOOL_OPTIONS: ..." notice (proxy settings
# in this container) — grepping for the `version "..."` token skips it regardless of whether that
# notice is present.
java_label="Java ?"
if [ -n "$JAVA" ]; then
    java_label="Java $("$JAVA" -version 2>&1 | grep -oE 'version "[0-9]+(\.[0-9]+)*' | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)"
fi
# LuaJIT's third version number is a git timestamp, not a patch level (e.g. 2.1.1703358377) — only
# major.minor is a meaningful label.
luajit_label="LuaJIT ?"
if [ -n "$LUAJIT" ]; then
    luajit_label="LuaJIT $("$LUAJIT" -v 2>&1 | grep -oE 'LuaJIT [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)"
fi
printf "│ Benchmark            │ %-12s │    Ollin     │ %-12s │ %-12s │ %-12s │\n" \
    "$lua_label" "$py_label" "$java_label" "$luajit_label"
echo "├──────────────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤"

ollin_times=()
lua_times=()
py_times=()
java_times=()
luajit_times=()

for b in "${benchmarks[@]}"; do
    if [ -x "$OLLIN" ]; then
        ollin_times+=("$(best_of "$OLLIN" "$DIR/bench_${b}.ol")")
    else
        ollin_times+=("N/A")
    fi
    if [ -n "$LUA" ] && [ -f "$DIR/bench_${b}.lua" ]; then
        lua_times+=("$(best_of "$LUA" "$DIR/bench_${b}.lua")")
    else
        lua_times+=("N/A")
    fi
    if [ -n "$PY" ] && [ -f "$DIR/bench_${b}.py" ]; then
        py_times+=("$(best_of "$PY" "$DIR/bench_${b}.py")")
    else
        py_times+=("N/A")
    fi
    if [ -n "$JAVA" ] && [ -f "$DIR/bench_${b}.java" ]; then
        java_times+=("$(best_of "$JAVA" "$DIR/bench_${b}.java")")
    else
        java_times+=("N/A")
    fi
    # LuaJIT runs the SAME .lua source as Lua — no bench_*.luajit file of its own.
    if [ -n "$LUAJIT" ] && [ -f "$DIR/bench_${b}.lua" ]; then
        luajit_times+=("$(best_of "$LUAJIT" "$DIR/bench_${b}.lua")")
    else
        luajit_times+=("N/A")
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

for i in "${!benchmarks[@]}"; do
    label="${labels[$i]}"
    ot="${ollin_times[$i]}"
    lt="${lua_times[$i]}"
    pt="${py_times[$i]}"
    jt="${java_times[$i]}"
    ljt="${luajit_times[$i]}"
    or=$(ratio "$ot" "$lt")
    pr=$(ratio "$pt" "$lt")
    jr=$(ratio "$jt" "$lt")
    ljr=$(ratio "$ljt" "$lt")
    pad=$((20 - ${#label}))
    printf "│ %s%*s │ %12s │ %12s │ %12s │ %12s │ %12s │\n" \
        "$label" "$pad" "" \
        "${lt:+${lt}s}" \
        "$or" \
        "$pr" \
        "$jr" \
        "$ljr"
done

echo "└──────────────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘"
if [ -n "${RAW:-}" ]; then
    echo ""
    for i in "${!benchmarks[@]}"; do
        printf "RAW %s %s %s %s %s %s\n" "${benchmarks[$i]}" "${lua_times[$i]}" "${ollin_times[$i]}" \
            "${py_times[$i]}" "${java_times[$i]}" "${luajit_times[$i]}"
    done
fi
echo ""
