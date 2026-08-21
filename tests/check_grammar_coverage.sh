#!/bin/bash
# COVERAGE guard: every rule of docs/grammar.ebnf must be cited by a `## [grammaire: …]`
# label in tests/syntax.ol.
#
# Why: nothing checked that syntax.ol still covers every form of the language — a file
# stripped of half its sections passed as "TOUT VERT", the suite doing no more than run it.
# Adding a production to the grammar without writing its test is now impossible (which had
# already happened with `enum`).
#
# What the script does NOT check: that the labelled section really exercises the form. It
# compares names and does not read the code — the label commits whoever writes it.
set -uo pipefail

racine=$(cd "$(dirname "$0")/.." && pwd)
grammaire="$racine/docs/grammar.ebnf"
tests="$racine/tests/syntax.ol"

# Rules deliberately exempted: purely lexical, with no form of their own to write — they
# exist only as parts of a token already covered.
exemptees=" "

manquantes=()
while read -r regle; do
    case "$exemptees" in *" $regle "*) continue ;; esac
    if ! grep -q "^## \[grammaire:.*\b${regle}\b" "$tests"; then
        manquantes+=("$regle")
    fi
done < <(grep -oE "^[a-zA-Z_]+ *=" "$grammaire" | sed 's/ *=//' | sort -u)

# The other direction: a label citing a name absent from the grammar (a typo, or a renamed
# rule) would go unnoticed and give false confidence.
inconnues=()
while read -r cite; do
    if ! grep -qE "^${cite} *=" "$grammaire"; then
        inconnues+=("$cite")
    fi
done < <(grep -oE "^## \[grammaire: [^]]+\]" "$tests" | sed 's/^## \[grammaire: //; s/\]$//' | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort -u)

if [ ${#manquantes[@]} -eq 0 ] && [ ${#inconnues[@]} -eq 0 ]; then
    total=$(grep -cE "^[a-zA-Z_]+ *=" "$grammaire")
    echo "OK   couverture grammaire ($total règles citées par tests/syntax.ol)"
    exit 0
fi

for r in ${manquantes[@]+"${manquantes[@]}"}; do
    echo "ECHEC  règle '$r' de grammar.ebnf citée par aucune étiquette de syntax.ol"
done
for r in ${inconnues[@]+"${inconnues[@]}"}; do
    echo "ECHEC  étiquette de syntax.ol citant '$r', qui n'est pas une règle de grammar.ebnf"
done
exit 1
