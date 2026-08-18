#!/usr/bin/env bash
# Run all benchmarks for Ollin, Lua, and Python 3.
# Usage: bash bench/bench_all.sh  (from repo root)
#        RUNS=5 bash bench/bench_all.sh   (override number of runs)
#
# Chaque benchmark est exécuté RUNS fois (défaut 3) et on garde le MEILLEUR
# temps : un seul run est trop sensible au bruit (contention CPU/cache) et
# peut afficher un coefficient faussé.

set -euo pipefail
# Alignement du tableau : ${#label} doit compter des CARACTÈRES et non des octets,
# sinon un label accentué (« chaînes ») ressort trop court. Sans locale UTF-8
# disponible, on retombe simplement sur ce léger décalage.
export LC_ALL=${LC_ALL:-C.UTF-8}
RUNS=${RUNS:-3}
OLLIN=$([ -x "./build/ollin" ] && echo "./build/ollin" || echo "./build/ollin.exe")
# Interpréteurs de comparaison : les versions viennent du fichier écrit par le hook de
# session, qui les a installées et les connaît donc exactement. Aucun numéro de version en
# dur ici, et aucune devinette sur les noms de binaires.
INTERP_ENV="$(dirname "$0")/../build/bench-interpreters.env"
LUA=""
PY=""
if [ -f "$INTERP_ENV" ]; then
    # shellcheck disable=SC1090
    . "$INTERP_ENV"
fi
# Repli hors conteneur (machine de développement, Windows) : le hook n'y tourne pas.
[ -n "$LUA" ] && command -v "$LUA" >/dev/null 2>&1 || LUA=$(command -v lua 2>/dev/null || echo "")
[ -n "$LUA" ] || { [ -x "/c/Tools/lua/lua55.exe" ] && LUA="/c/Tools/lua/lua55.exe"; }
[ -n "$PY" ] && command -v "$PY" >/dev/null 2>&1 || PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
DIR=$(dirname "$0")

extract_time() {
    echo "$1" | grep -oE 'time: [0-9]+\.[0-9]+' | sed 's/time: //'
}

# best_of <interp> <script> : lance le script RUNS fois, renvoie le meilleur
# (plus petit) temps extrait, ou "N/A" si aucun run n'a produit de temps.
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

benchmarks=(fib loop objects array calls strings classes iter float)
labels=("fib(35) récursif" "boucle 10M" "map 100K" "array 1M" "appels 1M"
        "chaînes 200K" "classes 200K" "iter 2.4M" "mandelbrot 200x200")

echo ""
echo "  (meilleur de $RUNS runs par benchmark)"
echo "┌──────────────────────┬──────────────┬──────────────┬──────────────┐"
# Version LUE sur l'interpréteur, jamais écrite en dur : l'en-tête annonçait « Lua 5.5 »
# quelle que soit la version mesurée, ce qui rendait le tableau faux dès que le conteneur
# fournissait une autre version.
lua_label="Lua ?"
if [ -n "$LUA" ]; then
    lua_label="Lua $("$LUA" -v 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
fi
py_label="Python ?"
if [ -n "$PY" ]; then
    py_label="Python $("$PY" -V 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
fi
printf "│ Benchmark            │ %-12s │    Ollin     │ %-12s │\n" "$lua_label" "$py_label"
echo "├──────────────────────┼──────────────┼──────────────┼──────────────┤"

ollin_times=()
lua_times=()
py_times=()

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
    or=$(ratio "$ot" "$lt")
    pr=$(ratio "$pt" "$lt")
    pad=$((20 - ${#label}))
    printf "│ %s%*s │ %12s │ %12s │ %12s │\n" \
        "$label" "$pad" "" \
        "${lt:+${lt}s}" \
        "$or" \
        "$pr"
done

echo "└──────────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""
