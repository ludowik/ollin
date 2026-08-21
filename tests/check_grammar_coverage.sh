#!/bin/bash
# COVERAGE guard: every rule of docs/grammar.ebnf must be cited by a `## [grammar: …]`
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

root=$(cd "$(dirname "$0")/.." && pwd)
grammar="$root/docs/grammar.ebnf"
tests="$root/tests/syntax.ol"

# Rules deliberately exempted: purely lexical, with no form of their own to write — they
# exist only as parts of a token already covered.
exempted=" "

missing=()
while read -r rule; do
    case "$exempted" in *" $rule "*) continue ;; esac
    if ! grep -q "^## \[grammar:.*\b${rule}\b" "$tests"; then
        missing+=("$rule")
    fi
done < <(grep -oE "^[a-zA-Z_]+ *=" "$grammar" | sed 's/ *=//' | sort -u)

# The other direction: a label citing a name absent from the grammar (a typo, or a renamed
# rule) would go unnoticed and give false confidence.
unknown=()
while read -r cited; do
    if ! grep -qE "^${cited} *=" "$grammar"; then
        unknown+=("$cited")
    fi
done < <(grep -oE "^## \[grammar: [^]]+\]" "$tests" | sed 's/^## \[grammar: //; s/\]$//' | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort -u)

if [ ${#missing[@]} -eq 0 ] && [ ${#unknown[@]} -eq 0 ]; then
    total=$(grep -cE "^[a-zA-Z_]+ *=" "$grammar")
    echo "OK   couverture grammaire ($total règles citées par tests/syntax.ol)"
    exit 0
fi

for r in ${missing[@]+"${missing[@]}"}; do
    echo "ECHEC  règle '$r' de grammar.ebnf citée par aucune étiquette de syntax.ol"
done
for r in ${unknown[@]+"${unknown[@]}"}; do
    echo "ECHEC  étiquette de syntax.ol citant '$r', qui n'est pas une règle de grammar.ebnf"
done
exit 1
