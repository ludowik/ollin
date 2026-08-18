#!/usr/bin/env bash
# Compte les INSTRUCTIONS exécutées, pour départager un coût réel d'un effet de placement.
#
# Pourquoi cet outil : les temps de bench_all.sh varient de ±7 % selon l'adresse à laquelle
# le compilateur place les gestionnaires d'opcodes (tous dans la seule fonction run_goto,
# computed-goto). Une régression de 4 % y est donc indétectable, et « c'est la disposition
# du code » devient une affirmation qu'on ne peut ni vérifier ni réfuter. Le nombre
# d'instructions exécutées, lui, ne dépend ni de l'adresse du code ni du cache : il mesure
# le TRAVAIL. Deux lectures possibles, et une seule demande une correction :
#
#   instructions en hausse   → coût réel : le moteur fait davantage de travail.
#   instructions stables     → placement : rien à optimiser, et figer une disposition
#                              favorable ne servirait à rien (le prochain commit la défera).
#
# Usage :
#   bash bench/icount.sh                          compte pour ./build/ollin
#   bash bench/icount.sh <réf-git>                compare ./build/ollin à ce commit
#   bash bench/icount.sh <réf-git> <autre-réf>    compare deux commits entre eux
#
# Sensibilité VÉRIFIÉE : quatre comparaisons ajoutées en tête de op_ADD (non éliminables par
# le compilateur) ressortent à +0,61 % sur fib — un surcoût que les temps de bench_all.sh
# auraient noyé dans leur bruit. Attention en écrivant une telle sonde : des tests
# contradictoires (`v.is_range() && v.is_iterator()`) sont supprimés à la compilation et ne
# mesurent RIEN, ce qui donnerait l'illusion d'un outil aveugle.
#
# Un commit passé en argument est construit dans un worktree jetable sous /tmp (retiré à la
# fin). Les scripts mesurés sont RÉDUITS par rapport à bench/ : callgrind ralentit d'environ
# 50×, et un compte d'instructions n'a pas besoin de longues séries — il est déterministe,
# donc une seule exécution suffit et donne le même chiffre à chaque fois.
set -uo pipefail

racine=$(cd "$(dirname "$0")/.." && pwd)
cd "$racine" || exit 1

if ! command -v valgrind >/dev/null 2>&1; then
    echo "valgrind est absent : sudo apt-get install -y valgrind"
    exit 1
fi

travail=$(mktemp -d)
scripts=""
# Les worktrees sont retrouvés par leur PRÉFIXE et non par une liste accumulée : `construire`
# est appelée dans une substitution de commande, donc dans un sous-shell — une variable
# qu'elle remplirait n'atteindrait jamais ce nettoyage (worktree laissé derrière, constaté).
nettoyer() {
    local w
    for w in $(git worktree list --porcelain | sed -n 's|^worktree /tmp/icount-|/tmp/icount-|p'); do
        git worktree remove --force "$w" >/dev/null 2>&1
    done
    rm -rf "$travail"
}
trap nettoyer EXIT

# Les trois chemins chauds qui se distinguent : appels et sauts conditionnels (fib),
# boucle numérique arithmétique (loop), map et itération (map).
mkdir -p "$travail/scripts"
cat > "$travail/scripts/fib.ol" <<'EOF'
func fib(n)
    if n <= 1 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end
print(fib(24))
EOF
cat > "$travail/scripts/loop.ol" <<'EOF'
var s = 0
for i = 1, 300000 do
    s += i
end
print(s)
EOF
cat > "$travail/scripts/map.ol" <<'EOF'
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

# Construit une référence git dans un worktree jetable et renvoie le chemin du binaire.
construire() {
    local ref="$1"
    local sha
    sha=$(git rev-parse --short "$ref" 2>/dev/null) || {
        echo "référence git inconnue : $ref" >&2
        return 1
    }
    local dir="/tmp/icount-$sha"
    rm -rf "$dir"
    git worktree add -q "$dir" "$sha" || return 1
    cmake -S "$dir" -B "$dir/build" -DCMAKE_BUILD_TYPE=Release -Wno-dev --log-level=ERROR >/dev/null 2>&1
    cmake --build "$dir/build" -j"$(nproc 2>/dev/null || echo 4)" --target ollin >/dev/null 2>&1 || {
        echo "compilation impossible pour $ref" >&2
        return 1
    }
    echo "$dir/build/ollin"
}

# Nombre d'instructions exécutées par <binaire> sur <script>. Déterministe.
compter() {
    valgrind --tool=callgrind --callgrind-out-file=/dev/null "$1" "$2" 2>&1 \
        | grep -oE "refs: *[0-9,]+" | tr -d ' ,' | sed 's/refs://'
}

courant=$([ -x "./build/ollin" ] && echo "./build/ollin" || echo "./build/ollin.exe")
if [ $# -ge 2 ]; then
    nom_a="$1"
    nom_b="$2"
    bin_a=$(construire "$1") || exit 1
    bin_b=$(construire "$2") || exit 1
elif [ $# -eq 1 ]; then
    nom_a="$1"
    nom_b="build/ollin"
    bin_a=$(construire "$1") || exit 1
    bin_b="$courant"
else
    nom_a=""
    nom_b="build/ollin"
    bin_b="$courant"
fi

echo ""
if [ -z "$nom_a" ]; then
    printf "  instructions exécutées — %s\n\n" "$nom_b"
    printf "  %-8s %16s\n" "script" "instructions"
    for s in $scripts; do
        printf "  %-8s %16s\n" "$s" "$(compter "$bin_b" "$travail/scripts/$s.ol")"
    done
    echo ""
    exit 0
fi

printf "  instructions exécutées — %s → %s\n" "$nom_a" "$nom_b"
printf "  (hausse = coût réel ; stable = placement du code, rien à optimiser)\n\n"
printf "  %-8s %16s %16s %10s\n" "script" "$nom_a" "$nom_b" "écart"
for s in $scripts; do
    a=$(compter "$bin_a" "$travail/scripts/$s.ol")
    b=$(compter "$bin_b" "$travail/scripts/$s.ol")
    if [ -z "$a" ] || [ -z "$b" ]; then
        printf "  %-8s %16s %16s %10s\n" "$s" "${a:-N/A}" "${b:-N/A}" "N/A"
        continue
    fi
    awk -v s="$s" -v a="$a" -v b="$b" 'BEGIN { printf "  %-8s %16d %16d %+9.2f%%\n", s, a, b, (b - a) / a * 100 }'
done
echo ""
