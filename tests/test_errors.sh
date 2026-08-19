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

check_error "tween.repeat with zero occurrences" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat(0)' \
    "entier >= 1"

check_error "tween.repeat with a fractional count" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat(2.5)' \
    "entier >= 1"

check_error "tween.repeat with a non-numeric count" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat("deux")' \
    "un nombre ou nil"

check_error "ui.list without a reference" \
    'global v = nil
ui.list("Couleur", ["a", "b"], v)' \
    "must be a reference"

check_error "ui.list with a bad source" \
    'global v = nil
ui.list("Couleur", 3, ref v)' \
    "must be an array, a map or an enum"

check_error "ui.list with an empty source" \
    'global v = nil
ui.list("Couleur", [], ref v)' \
    "list is empty"

# ── Booléens : type étanche ────────────────────────────────────────────────────
# L'étanchéité tient à un point de passage unique (VM::as_double) : l'arithmétique et les
# comparaisons d'ordre refusent le booléen comme elles refusent nil.

check_error "arithmetic on a boolean" \
    'print(true + 1)' \
    "expected number, got boolean"

check_error "boolean on the right of an addition" \
    'print(1 + true)' \
    "expected number, got boolean"

check_error "negating a boolean" \
    'print(-true)' \
    "expected number, got boolean"

check_error "ordering two booleans" \
    'print(true < false)' \
    "expected number, got boolean"

check_error "comparing a boolean with a number by order" \
    'print(true >= 1)' \
    "expected number, got boolean"

check_error "compound assignment on a boolean" \
    'var b = true
b *= 2' \
    "expected number, got boolean"

# ── tween.sequence ─────────────────────────────────────────────────────────────
# Une clé inconnue est REFUSÉE avec la liste des clés admises : sans ce refus, un
# `duration` ou un `easing` mal choisi serait ignoré en silence et l'étape partirait sans
# durée. C'est la faute qu'on cherche le plus longtemps.

check_error "tween.sequence with an unknown step key" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, duration: 1}])' \
    "clé inconnue 'duration'"

check_error "tween.sequence with an empty list" \
    'global o = {x: 0}
tween.sequence(o, [])' \
    "séquence est vide"

check_error "tween.sequence with a step that is not a map" \
    'global o = {x: 0}
tween.sequence(o, [3])' \
    "doit être une map"

check_error "tween.sequence with a missing delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}}])' \
    "manquant ou <= 0"

check_error "tween.sequence with a negative delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: -1}])' \
    "manquant ou <= 0"

check_error "tween.sequence with a non-numeric delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: "vite"}])' \
    "doit être un nombre de secondes"

check_error "tween.sequence with an absent field" \
    'global o = {x: 0}
tween.sequence(o, [{to: {absent: 1}, delay: 1}])' \
    "est absent de l'objet"

check_error "tween.sequence with a list that is not an array" \
    'global o = {x: 0}
tween.sequence(o, {to: {x: 1}})' \
    "tableau d'étapes"

check_error "tween.sequence with a curve after the list" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1}], "easeInOutQuad")' \
    "courbe se déclare par étape"

check_error "tween.sequence with two end callbacks" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1}], func() end, func() end)' \
    "un seul rappel de fin"

check_error "tween.sequence with an unknown curve" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1, curve: "aucune"}])' \
    "courbe inconnue"

check_error "tween.sequence with a tween as target" \
    'global o = {x: 0}
var inner = tween.sequence(o, [{to: {x: 1}, delay: 1}])
tween.sequence(o, [{to: inner, delay: 1}])' \
    "ne s'imbrique pas"

check_error "tween.to on a tween handle" \
    'global o = {x: 0}
var t = tween.to(o, {x: 1}, 1)
tween.to(t, {x: 1}, 1)' \
    "ne peut pas être l'objet animé"

# ── modules audio / sound ────────────────────────────────────────────────────
check_error "audio.volume with a string" \
    'audio.volume("fort")' \
    "expected a number between 0 and 1"

check_error "sound.osc with an unknown waveform" \
    'sound.osc(440, "bruit")' \
    "forme d'onde inconnue"

check_error "sound.osc above the audible range" \
    'sound.osc(30000)' \
    "hors de [0;20000]"

check_error "sound.osc with a negative frequency" \
    'sound.osc(-5)' \
    "hors de [0;20000]"

check_error "sound.osc with a non-numeric frequency" \
    'sound.osc("la")' \
    "doit être un nombre de hertz"

check_error "sound.shape with a number" \
    'var o = sound.sine(440)
o.shape(3)' \
    "doit être un nom"

check_error "sound.volume with a string" \
    'var o = sound.sine(440)
o.volume("fort")' \
    "le volume doit être un nombre"

check_error "oscillator recycled while its handle is kept" \
    'var vieux = sound.sine(200)
for i = 1, 20 do
    sound.sine(300)
end
vieux.freq()' \
    "existe plus"

check_error "sound.envelope with a negative time" \
    'sound.sine(440).envelope(-1, 0.1, 0.5, 0.1)' \
    "aucune valeur ne peut être négative"

check_error "sound.envelope with a sustain above 1" \
    'sound.sine(440).envelope(0.1, 0.1, 5, 0.1)' \
    "le maintien est un niveau"

check_error "sound.envelope with too few values" \
    'sound.sine(440).envelope(0.1, 0.1)' \
    "attendu attaque, déclin, maintien, relâchement"

check_error "sound.trigger with a zero duration" \
    'sound.sine(440).trigger(0)' \
    "la durée doit être > 0"

check_error "sound.tone without a duration" \
    'sound.tone(440)' \
    "la durée doit être un nombre de secondes"

check_error "sound.tone with too long a duration" \
    'sound.tone(440, 60)' \
    "la durée dépasse 10 secondes"

check_error "sound.generate without a function" \
    'sound.generate(0.1, 42)' \
    "une fonction du temps"

check_error "sound.rate out of range" \
    'sound.tone(440, 0.1).rate(0)' \
    "vitesse hors de"

check_error "sound.loop with a number" \
    'sound.tone(440, 0.1).loop(3)' \
    "attendu true, false, ou aucun argument"

check_error "sound.sample without a time" \
    'sound.tone(440, 0.1).sample()' \
    "attendu un temps en secondes"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
