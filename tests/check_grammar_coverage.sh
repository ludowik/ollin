#!/bin/bash
# Garde-fou de COUVERTURE : chaque règle de docs/grammar.ebnf doit être citée par une
# étiquette `## [grammaire: …]` de tests/syntax.ol.
#
# Pourquoi : rien ne vérifiait que syntax.ol couvre encore toutes les formes du langage —
# un fichier amputé de la moitié de ses sections passait « TOUT VERT », puisque la suite se
# contente de l'exécuter. Ajouter une production à la grammaire sans écrire son test
# devient maintenant impossible (cas déjà survenu avec `enum`).
#
# Ce que le script NE vérifie PAS : que la section étiquetée exerce réellement la forme.
# Il compare des noms, il ne lit pas le code — l'étiquette engage celui qui la pose.
set -uo pipefail

racine=$(cd "$(dirname "$0")/.." && pwd)
grammaire="$racine/docs/grammar.ebnf"
tests="$racine/tests/syntax.ol"

# Règles volontairement exemptées : purement lexicales et sans forme propre à écrire —
# elles n'existent que comme sous-parties d'un token déjà couvert.
exemptees=" "

manquantes=()
while read -r regle; do
    case "$exemptees" in *" $regle "*) continue ;; esac
    if ! grep -q "^## \[grammaire:.*\b${regle}\b" "$tests"; then
        manquantes+=("$regle")
    fi
done < <(grep -oE "^[a-zA-Z_]+ *=" "$grammaire" | sed 's/ *=//' | sort -u)

# Sens inverse : une étiquette qui cite un nom absent de la grammaire (faute de frappe ou
# règle renommée) passerait inaperçue et donnerait une fausse assurance.
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
