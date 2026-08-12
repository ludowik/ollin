#!/bin/bash
# Vérifie que le compilateur rejette les redéclarations et assignations illégales
OLLIN=./build/ollin
PASS=0
FAIL=0

check_error() {
    local desc="$1"
    local code="$2"
    local expected="$3"
    local actual
    actual=$(echo "$code" | $OLLIN /dev/stdin 2>&1)
    if echo "$actual" | grep -qF "$expected"; then
        echo "OK  $desc"
        PASS=$((PASS+1))
    else
        echo "FAIL $desc"
        echo "     expected: $expected"
        echo "     got:      $actual"
        FAIL=$((FAIL+1))
    fi
}

check_error "local redeclaration" \
    'var x = 1
var x = 2' \
    "local variable 'x' already declared in this scope"

check_error "local redeclaration inside function" \
    'func f()
    var y = 1
    var y = 2
end' \
    "local variable 'y' already declared in this scope"

check_error "param redeclaration via var" \
    'func f(a)
    var a = 1
end' \
    "local variable 'a' already declared in this scope"

check_error "var utilisée avant sa déclaration (top-level)" \
    'print(z)
var z = 1' \
    "undeclared variable 'z'"

check_error "var utilisée avant sa déclaration (dans fonction)" \
    'func f()
    print(w)
    var w = 1
end' \
    "undeclared variable 'w'"

check_error "global redeclaration" \
    'global g = 1
global g = 2' \
    "global variable 'g' already declared"

check_error "global redeclaration across functions" \
    'global h = 1
func f()
    global h = 2
end' \
    "global variable 'h' already declared"

check_error "const sans init" \
    'const x' \
    "must be initialized"

check_error "const reassignment direct" \
    'const x = 1
x = 2' \
    "cannot assign to const 'x'"

check_error "const compound assignment" \
    'const x = 10
x += 1' \
    "cannot assign to const 'x'"

check_error "const reassignment inside function" \
    'const k = 42
func f()
    k = 0
end' \
    "cannot assign to const 'k'"

# ── littéraux numériques malformés ────────────────────────────────────────────
check_error "octal digit invalide"      'print(0o18)'   "invalid octal literal"
check_error "octal 9"                    'print(0o9)'    "invalid octal literal"
check_error "hex lettre invalide"        'print(0xFFg)'  "invalid hexadecimal literal"
check_error "hex point colle"            'print(0x1.5)'  "invalid hexadecimal literal"
check_error "hex underscore en tete"     'print(0x_FF)'  "invalid hexadecimal literal"
check_error "hex underscore final"       'print(0xFF_)'  "invalid hexadecimal literal"
check_error "hex underscore double"      'print(0xF__F)' "invalid hexadecimal literal"
check_error "hex sans chiffre"           'print(0x)'     "invalid hexadecimal literal"
check_error "binaire chiffre invalide"   'print(0b2)'    "invalid binary literal"
check_error "binaire sans chiffre"       'print(0b)'     "invalid binary literal"
check_error "binaire underscore final"   'print(0b1_)'   "invalid binary literal"
check_error "** supprimé (puissance = ^)" 'print(2 ** 3)' "utilisez '^' pour la puissance"
check_error "decimal alnum colle"        'print(42abc)'  "invalid number literal"
check_error "decimal underscore final"   'print(1_)'     "invalid number literal"
check_error "decimal underscore double"  'print(1__0)'   "invalid number literal"
check_error "decimal double point"       'print(1.2.3)'  "invalid number literal"
check_error "exposant sans chiffre"      'print(1e)'     "invalid number literal"
check_error "exposant signe sans chiffre" 'print(1e+)'   "invalid number literal"
check_error "exposant underscore avant"  'print(1_e5)'   "invalid number literal"
check_error "double exposant"            'print(1e5e6)'  "invalid number literal"
check_error "exposant puis point"        'print(1e5.0)'  "invalid number literal"
check_error "hex hors limites"           'print(0xFFFFFFFFFFFFFFFFF)'      "out of range"
check_error "decimal hors limites"       'print(99999999999999999999999)' "out of range"

# ── appel optionnel : non-nil non-callable → erreur (nil seul est ignoré) ──────
check_error "appel optionnel sur entier" \
    'var x = 42
print(x?())' \
    "call on non-function value"
check_error "methode optionnelle sur champ data" \
    'class A
    func init() self.x = 7 end
end
var a = A()
print(a.x?())' \
    "method call on non-function value"

# ── la variable de boucle est locale à la boucle (pas de fuite après) ──────────
check_error "var for numérique non visible après" \
    'for i = 1, 3 do end
print(i)' \
    "undeclared variable 'i'"
check_error "var for itérateur non visible après" \
    'for k, v in {a: 1} do end
print(k)' \
    "undeclared variable 'k'"

# ── enum ─────────────────────────────────────────────────────────────────────
check_error "enum element declared twice" \
    'enum E A, B, A end' \
    "element 'A' declared twice"

check_error "enum write refused at compile time" \
    'enum E A, B end
E.A = 5' \
    "cannot modify enum 'E' element 'A'"

check_error "enum write through computed key" \
    'enum E A, B end
var k = "A"
E[k] = 5' \
    "cannot modify enum 'E'"

check_error "enum write in multi-assignment" \
    'enum E A, B end
var x = 0
E.A, x = 1, 2' \
    "cannot modify enum 'E' element 'A'"

check_error "enum write before its declaration" \
    'func f()
    E.A = 1
end
enum E A, B end
f()' \
    "cannot modify enum 'E' element 'A'"

check_error "enum write through alias (runtime guard)" \
    'enum E A, B end
var m = E
m.A = 5' \
    "cannot modify an enum"

check_error "enum delete refused" \
    'enum E A, B end
var m = E
m.A = nil' \
    "cannot modify an enum"


# ── ref ──────────────────────────────────────────────────────────────────────
check_error "ref on undeclared variable" \
    'var r = ref inconnue' \
    "undeclared variable 'inconnue'"

check_error "ref on a literal" \
    'var r = ref 42' \
    "ref attend un nom de variable"

check_error "ref with index" \
    'var t = [1, 2]
var r = ref t[1]' \
    "chemin de champs"


# ── module ui ────────────────────────────────────────────────────────────────
check_error "ui.checkbox without a reference" \
    'global g = true
ui.checkbox("Grille", g)' \
    "must be a reference"

check_error "ui.button without a function" \
    'ui.button("Rejouer", 42)' \
    "must be a function"

check_error "ui.button label not a string" \
    'func f() end
ui.button(42, f)' \
    "label must be a string"

check_error "ui.menu label not a string" \
    'var m = ui.menu(42)' \
    "label must be a string"

check_error "ui.slider without a reference" \
    'global v = 1
ui.slider("Taille", v, 1, 10)' \
    "must be a reference"

check_error "ui.slider with min >= max" \
    'global v = 1
ui.slider("Taille", ref v, 10, 1)' \
    "min must be smaller than max"

check_error "ui.slider bounds not numbers" \
    'global v = 1
ui.slider("Taille", ref v, "a", 10)' \
    "must be numbers"


check_error "tween.to with zero duration" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 0)' \
    "durée doit être > 0"

check_error "tween.to with unknown curve" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1, "rebond")' \
    "courbe inconnue"

check_error "tween.to on a missing field" \
    'global o = {x: 0}
tween.to(o, {y: 1}, 1)' \
    "absent de"

check_error "tween.to on a non-interpolable value" \
    'global o = {x: "a"}
tween.to(o, {x: 1}, 1)' \
    "pas interpolable"

check_error "tween.value without a reference" \
    'global v = 1
tween.value(v, 10, 1)' \
    "doit être une référence"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
