#!/bin/bash
# Garde-fou de nommage — DEUX sens :
#
#  1. API Ollin exposée : tout nom de fonction/méthode exposé par un module
#     (1er argument de map_set(..., make(_static)_builtin)) doit être en camelCase
#     (fonctions) ou PascalCase (constructeurs : Color, Quat…) — JAMAIS snake_case.
#     Noms méta (__str, __class__, __name__) exclus.
#
#  2. C++ interne : le code du moteur est en snake_case. Aucun identifiant camelCase
#     ne doit apparaître dans le CODE (hors chaînes/commentaires), à l'exception des
#     identifiants EXTERNES : API raylib/rlgl (rl*/gl*), méthodes emscripten::val
#     (isNumber…), champs de structs raylib (vaoId, texId, meshMaterial…).
#
# Convention : voir CLAUDE.md (« Conventions de nommage »).
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

bad=0

# ── 1. API exposée = camelCase ──────────────────────────────────────────────
names=$(grep -rhoE 'map_set\(Value\(std::string\("[A-Za-z_][A-Za-z0-9_]*"\)\), Value::make_(static_)?builtin' src/modules/*.cpp \
        | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u)
for n in $names; do
    case "$n" in
        __*) continue ;;   # méta-méthodes / clés internes
    esac
    if [[ "$n" == *_* ]]; then
        echo "NAMING: API '$n' contient un '_' — l'API Ollin doit être en camelCase"
        bad=$((bad + 1))
    fi
done

# ── 2. C++ interne = snake_case (aucun camelCase hors externes) ──────────────
residue=$(python3 - "$root" <<'PY'
import re, sys, os, glob
root = sys.argv[1]

def strip(text):
    # Remplace chaînes / char / raw-strings / commentaires par des espaces
    # (préserve les décalages) afin de n'analyser que le CODE réel.
    out = []; i = 0; n = len(text)
    while i < n:
        c = text[i]
        # Bloc EM_ASM(...) : c'est du JavaScript stringifié par la macro (pas du C++)
        # → neutraliser toute la portée (parenthèses équilibrées, en ignorant
        # commentaires et chaînes internes). Sinon ses identifiants JS (getElementById,
        # srcObject…) seraient pris pour du camelCase C++.
        ma = re.match(r'\b(?:MAIN_THREAD_)?EM_ASM\w*\s*\(', text[i:])
        if ma:
            k = i + ma.end() - 1  # position du '('
            depth = 0; j = k
            while j < n:
                cj = text[j]
                if cj == '/' and j + 1 < n and text[j + 1] == '/':
                    e = text.find('\n', j); j = n if e < 0 else e; continue
                if cj == '/' and j + 1 < n and text[j + 1] == '*':
                    e = text.find('*/', j + 2); j = n if e < 0 else e + 2; continue
                if cj in '"\'':
                    j += 1
                    while j < n:
                        if text[j] == '\\': j += 2; continue
                        if text[j] == cj: j += 1; break
                        j += 1
                    continue
                if cj == '(': depth += 1
                elif cj == ')':
                    depth -= 1
                    if depth == 0: j += 1; break
                j += 1
            out.append(' ' * (j - i)); i = j; continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j; continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append(' ' * (j - i)); i = j; continue
        m = re.match(r'(?:u8|u|U|L)?R"([^ ()\\\t]*)\(', text[i:])
        if m:
            close = ')' + m.group(1) + '"'
            j = text.find(close, i + m.end()); j = n if j < 0 else j + len(close)
            out.append(' ' * (j - i)); i = j; continue
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == '\\': j += 2; continue
                if text[j] == '"': j += 1; break
                j += 1
            out.append(' ' * (j - i)); i = j; continue
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == '\\': j += 2; continue
                if text[j] == "'": j += 1; break
                j += 1
            out.append(' ' * (j - i)); i = j; continue
        out.append(c); i += 1
    return ''.join(out)

# Externes autorisés : API emscripten::val + champs de structs raylib.
ALLOW = {
    'isNull', 'isNumber', 'isUndefined', 'isString', 'isArray', 'isTrue', 'isFalse',
    'blendMode', 'materialCount', 'meshCount', 'meshMaterial', 'texId',
    'triangleCount', 'vaoId', 'vboId', 'vertexCount', 'boneCount', 'baseSize',
}
def is_ext(t):
    if t in ALLOW: return True
    if t.startswith('rl') and len(t) > 2 and t[2].isupper(): return True   # rlgl
    if t.startswith('gl') and len(t) > 2 and t[2].isupper(): return True   # GL
    return False

files = glob.glob(os.path.join(root, 'src', '**', '*.cpp'), recursive=True) \
      + glob.glob(os.path.join(root, 'src', '**', '*.h'), recursive=True)
# Fichiers GÉNÉRÉS par un outil externe : leurs identifiants sont ceux de l'outil, pas
# des choix du projet, et une correction serait effacée à la prochaine génération.
GENERATED = {'ui_font.h'}
files = [f for f in files if os.path.basename(f) not in GENERATED]
seen = {}
for f in files:
    code = strip(open(f).read())
    for i, line in enumerate(code.split('\n'), 1):
        for m in re.finditer(r'\b[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*\b', line):
            t = m.group(0)
            if not is_ext(t):
                seen.setdefault(t, (os.path.relpath(f, root), i))
for t, (f, ln) in sorted(seen.items()):
    print(f"{t}\t{f}:{ln}")
PY
)
if [ -n "$residue" ]; then
    while IFS=$'\t' read -r tok loc; do
        echo "NAMING: identifiant interne '$tok' en camelCase ($loc) — le C++ interne doit être en snake_case"
        bad=$((bad + 1))
    done <<< "$residue"
fi

if [ $bad -eq 0 ]; then
    echo "OK   nommage (API camelCase ; C++ interne snake_case)"
    exit 0
fi
echo "$bad nom(s) non conforme(s)"
exit 1
