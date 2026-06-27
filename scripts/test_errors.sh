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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
