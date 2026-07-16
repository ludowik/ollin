#!/bin/bash
# Garde-fou de nommage de l'API Ollin : tout nom de fonction/méthode EXPOSÉ par un
# module (graphics, math, image, …) doit être en camelCase (fonctions) ou PascalCase
# (constructeurs : Color, Quat…) — JAMAIS en snake_case. Empêche la dérive historique
# (ex. begin_draw à côté de beginChunk). Les noms méta (__str, __class__, __name__)
# sont exclus. Convention côté langage/API : voir CLAUDE.md.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

# Noms exposés = 1er argument de mapSet(...) associé à un makeBuiltin/makeStaticBuiltin.
names=$(grep -rhoE 'mapSet\(Value\(std::string\("[A-Za-z_][A-Za-z0-9_]*"\)\), Value::make(Static)?Builtin' src/modules/*.cpp \
        | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u)

bad=0
for n in $names; do
    case "$n" in
        __*) continue ;;   # méta-méthodes / clés internes (__str, __class__, __name__)
    esac
    if [[ "$n" == *_* ]]; then
        echo "NAMING: '$n' contient un '_' — l'API Ollin doit être en camelCase (pas de snake_case)"
        bad=$((bad + 1))
    fi
done

if [ $bad -eq 0 ]; then
    echo "OK   nommage API (camelCase, aucun snake_case)"
    exit 0
fi
echo "$bad nom(s) d'API non conforme(s)"
exit 1
