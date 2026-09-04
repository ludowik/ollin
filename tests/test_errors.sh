#!/bin/bash
# Checks that the compiler rejects illegal redeclarations and assignments
OLLIN=./build/ollin
PASS=0
FAIL=0

# Same as check_error, but the code lives in a FILE: an import resolves against the importing
# file's directory, which /dev/stdin does not have.
check_error_file() {
    local desc="$1"
    local file="$2"
    local expected="$3"
    local actual
    actual=$($OLLIN "$file" 2>&1)
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

check_error "a var used above its declaration (top level)" \
    'print(z)
var z = 1' \
    "undeclared variable 'z'"

check_error "a var used above its declaration (inside a function)" \
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

# Two DIFFERENT modules under one alias in one scope is a genuine contradiction, and the message
# names both files instead of talking about a local variable.
check_error_file "two modules under one alias" tests/alias_clash_test.ol \
    "is already imported under that name in this scope"

# Every target of a multiple assignment must be an lvalue, the same rule as a single assignment.
check_error "a call as a multiple-assignment target" \
    'var x = 0
func f()
    return 1
end
f(), x = 1, 2' \
    "invalid assignment target"
check_error "an expression as a multiple-assignment target" \
    'var x = 0
var y = 0
x + 1, y = 1, 2' \
    "invalid assignment target"

# The comma between two items of a literal is mandatory (grammar.ebnf): newlines are not tokens,
# so without it "[1 2 3]" quietly read as three elements. One before the closing bracket is fine.
check_error "an array without a comma"    'var a = [1 2 3]'      "expected ',' between array elements"
check_error "a map without a comma"       'var m = {a: 1 b: 2}'  "expected ',' between map entries"

# A const stays a const through a multi-return destructuring: the early return of that path
# skipped the registration, and the write below went through in silence.
check_error "const through a multi-return destructuring" \
    'func f() return 1, 2 end
const a, b = f()
a = 99' \
    "cannot assign to const 'a'"

# A keyword spells a NAME as a map key or a field, but true/false/nil are left out: they carry
# a value, so ["true"] must be written out rather than turned into a string in silence.
check_error "true as a map-literal key"   'var m = {true: 1}'   "expected string, identifier, or [expr] key in map literal"
check_error "nil as a map-literal key"    'var m = {nil: 1}'    "expected string, identifier, or [expr] key in map literal"
check_error "a keyword as a variable name" 'var end = 1'        "unexpected token 'end'"
check_error "a field with no name"        'var m = {}
print(m.)'                                                      "expected a field name"

# Malformed numeric literals.
check_error "an octal literal with an invalid digit"      'print(0o18)'   "invalid octal literal"
check_error "octal 9"                    'print(0o9)'    "invalid octal literal"
check_error "a hex literal with an invalid letter"        'print(0xFFg)'  "invalid hexadecimal literal"
check_error "a hex literal with a dot stuck to it"            'print(0x1.5)'  "invalid hexadecimal literal"
check_error "hex underscore en tete"     'print(0x_FF)'  "invalid hexadecimal literal"
check_error "hex underscore final"       'print(0xFF_)'  "invalid hexadecimal literal"
check_error "hex underscore double"      'print(0xF__F)' "invalid hexadecimal literal"
check_error "a hex literal with no digit"           'print(0x)'     "invalid hexadecimal literal"
check_error "binary literal with an invalid digit"   'print(0b2)'    "invalid binary literal"
check_error "a binary literal with no digit"       'print(0b)'     "invalid binary literal"
check_error "a binary literal ending in an underscore"   'print(0b1_)'   "invalid binary literal"
check_error "** removed, exponentiation being ^" 'print(2 ** 3)' "use '^' for exponentiation"
check_error "a decimal literal with letters stuck to it"        'print(42abc)'  "invalid number literal"
check_error "decimal underscore final"   'print(1_)'     "invalid number literal"
check_error "decimal underscore double"  'print(1__0)'   "invalid number literal"
check_error "decimal double point"       'print(1.2.3)'  "invalid number literal"
check_error "an exponent with no digit"      'print(1e)'     "invalid number literal"
check_error "a signed exponent with no digit" 'print(1e+)'   "invalid number literal"
check_error "an underscore before the exponent"  'print(1_e5)'   "invalid number literal"
check_error "a double exponent"            'print(1e5e6)'  "invalid number literal"
check_error "an exponent followed by a dot"        'print(1e5.0)'  "invalid number literal"
check_error "a hex literal out of range"           'print(0xFFFFFFFFFFFFFFFFF)'      "out of range"
check_error "a decimal literal out of range"       'print(99999999999999999999999)' "out of range"

# Optional call: a non-nil, non-callable value is an error (only nil is ignored).
check_error "an optional call on an integer" \
    'var x = 42
print(x?())' \
    "call on non-function value"
check_error "an optional method on a data field" \
    'class A
    func init() self.x = 7 end
end
var a = A()
print(a.x?())' \
    "method call on non-function value"

# The loop variable is local to the loop, and does not leak afterwards.
check_error "a numeric for variable is not visible afterwards" \
    'for i = 1, 3 do end
print(i)' \
    "undeclared variable 'i'"
check_error "an iterator for variable is not visible afterwards" \
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
    'var r = ref unknown_name' \
    "undeclared variable 'unknown_name'"

check_error "ref on a literal" \
    'var r = ref 42' \
    "ref expects a variable name"

check_error "ref with index" \
    'var t = [1, 2]
var r = ref t[1]' \
    "path of fields"


# ── module ui ────────────────────────────────────────────────────────────────
check_error "ui.checkbox without a reference" \
    'global g = true
ui.checkbox("Grille", g)' \
    "must be a reference"

check_error "ui.button without a function" \
    'ui.button("Replay", 42)' \
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
ui.slider("Size", v, 1, 10)' \
    "must be a reference"

check_error "ui.slider with min >= max" \
    'global v = 1
ui.slider("Size", ref v, 10, 1)' \
    "min must be smaller than max"

check_error "ui.slider bounds not numbers" \
    'global v = 1
ui.slider("Size", ref v, "a", 10)' \
    "must be numbers"


check_error "tween.to with zero duration" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 0)' \
    "duration must be > 0"

check_error "tween.to with unknown curve" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1, "bounce_not_a_curve")' \
    "unknown curve"

check_error "tween.to on a missing field" \
    'global o = {x: 0}
tween.to(o, {y: 1}, 1)' \
    "missing from"

check_error "tween.to on a non-interpolable value" \
    'global o = {x: "a"}
tween.to(o, {x: 1}, 1)' \
    "cannot be interpolated"

check_error "tween.value without a reference" \
    'global v = 1
tween.value(v, 10, 1)' \
    "must be a reference"

check_error "tween.repeat with zero occurrences" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat(0)' \
    "integer >= 1"

check_error "tween.repeat with a fractional count" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat(2.5)' \
    "integer >= 1"

check_error "tween.repeat with a non-numeric count" \
    'global o = {x: 0}
tween.to(o, {x: 1}, 1).repeat("two")' \
    "a number or nil"

check_error "ui.list without a reference" \
    'global v = nil
ui.list("Colour", ["a", "b"], v)' \
    "must be a reference"

check_error "ui.list with a bad source" \
    'global v = nil
ui.list("Colour", 3, ref v)' \
    "must be an array, a map or an enum"

check_error "ui.list with an empty source" \
    'global v = nil
ui.list("Colour", [], ref v)' \
    "list is empty"

# Booleans: a sealed type. The sealing rests on a single point of passage (VM::as_double):
# arithmetic and the ordering comparisons refuse a boolean as they refuse nil.

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
# An unknown key is REFUSED, with the list of the accepted ones: without that refusal a
# mistaken `duration` or `easing` would be silently ignored and the step would start with no
# duration. That is the mistake one hunts for longest.

check_error "tween.sequence with an unknown step key" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, duration: 1}])' \
    "unknown key 'duration'"

check_error "tween.sequence with an empty list" \
    'global o = {x: 0}
tween.sequence(o, [])' \
    "sequence is empty"

check_error "tween.sequence with a step that is not a map" \
    'global o = {x: 0}
tween.sequence(o, [3])' \
    "must be a map"

check_error "tween.sequence with a missing delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}}])' \
    "missing or <= 0"

check_error "tween.sequence with a negative delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: -1}])' \
    "missing or <= 0"

check_error "tween.sequence with a non-numeric delay" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: "fast"}])' \
    "must be a number of seconds"

check_error "tween.sequence with an absent field" \
    'global o = {x: 0}
tween.sequence(o, [{to: {absent: 1}, delay: 1}])' \
    "is missing from the object"

check_error "tween.sequence with a list that is not an array" \
    'global o = {x: 0}
tween.sequence(o, {to: {x: 1}})' \
    "array of steps"

check_error "tween.sequence with a curve after the list" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1}], "easeInOutQuad")' \
    "curve is declared per step"

check_error "tween.sequence with two end callbacks" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1}], func() end, func() end)' \
    "only one completion callback"

check_error "tween.sequence with an unknown curve" \
    'global o = {x: 0}
tween.sequence(o, [{to: {x: 1}, delay: 1, curve: "no_such_curve"}])' \
    "unknown curve"

check_error "tween.sequence with a tween as target" \
    'global o = {x: 0}
var inner = tween.sequence(o, [{to: {x: 1}, delay: 1}])
tween.sequence(o, [{to: inner, delay: 1}])' \
    "do not nest"

check_error "tween.to on a tween handle" \
    'global o = {x: 0}
var t = tween.to(o, {x: 1}, 1)
tween.to(t, {x: 1}, 1)' \
    "cannot be the animated object"

# ── modules audio / sound ────────────────────────────────────────────────────
check_error "audio.volume with a string" \
    'audio.volume("fort")' \
    "expected a number between 0 and 1"

check_error "sound.osc with an unknown waveform" \
    'sound.osc(440, "bruit")' \
    "unknown waveform"

check_error "sound.osc above the audible range" \
    'sound.osc(30000)' \
    "out of [0;20000]"

check_error "sound.osc with a negative frequency" \
    'sound.osc(-5)' \
    "out of [0;20000]"

check_error "sound.osc with a frequency that is neither a number nor a note" \
    'sound.osc({})' \
    "a number of hertz or a note name"

check_error "sound.osc with an unreadable note name" \
    'sound.osc("la")' \
    "unknown note"

check_error "sound.shape with a number" \
    'var o = sound.sine(440)
o.shape(3)' \
    "must be a name"

check_error "sound.volume with a string" \
    'var o = sound.sine(440)
o.volume("fort")' \
    "volume must be a number"

check_error "oscillator recycled while its handle is kept" \
    'var vieux = sound.sine(200)
for i = 1, 20 do
    sound.sine(300)
end
vieux.freq()' \
    "no longer exists"

check_error "sound.envelope with a negative time" \
    'sound.sine(440).envelope(-1, 0.1, 0.5, 0.1)' \
    "no value may be negative"

check_error "sound.envelope with a sustain above 1" \
    'sound.sine(440).envelope(0.1, 0.1, 5, 0.1)' \
    "sustain is a level"

check_error "sound.envelope with too few values" \
    'sound.sine(440).envelope(0.1, 0.1)' \
    "expected attack, decay, sustain, release"

check_error "sound.trigger with a zero duration" \
    'sound.sine(440).trigger(0)' \
    "duration must be > 0"

check_error "sound.tone without a duration" \
    'sound.tone(440)' \
    "duration must be a number of seconds"

check_error "sound.tone with too long a duration" \
    'sound.tone(440, 60)' \
    "duration exceeds 10 seconds"

check_error "sound.generate without a function" \
    'sound.generate(0.1, 42)' \
    "a function of time"

check_error "sound.rate out of range" \
    'sound.tone(440, 0.1).rate(0)' \
    "rate out of"

check_error "sound.loop with a number" \
    'sound.tone(440, 0.1).loop(3)' \
    "expected true, false, or no argument"

check_error "sound.sample without a time" \
    'sound.tone(440, 0.1).sample()' \
    "expected a time in seconds"

check_error "sound.note with a letter beyond G" \
    'sound.note("H4")' \
    "unknown note"

check_error "sound.note without an octave" \
    'sound.note("A")' \
    "has no octave"

check_error "sound.note with an octave out of range" \
    'sound.note("A12")' \
    "octave out of"

check_error "sound.note with a number" \
    'sound.note(440)' \
    "expected a note name"

check_error "assert with a non-string message" \
    'assert(false, 42)' \
    "the message must be a string"

check_error "assert with a non-string message, condition true" \
    'assert(true, 42)' \
    "the message must be a string"

check_error "break inside a switch" \
    'for i = 1, 2 do
switch i
case 1
break
end
end' \
    "break inside a switch"

check_error "break inside a lambda declared in a loop" \
    'for i = 1, 2 do
var f = func()
break
end
end' \
    "break outside loop"

check_error "continue inside a lambda declared in a loop" \
    'for i = 1, 2 do
var f = func()
continue
end
end' \
    "continue outside loop"

check_error "date.now with a non-number instant" \
    'var d = date.now("today")' \
    "date.now: argument 1 expected number"

check_error "date.utc with a non-number instant" \
    'var d = date.utc([])' \
    "date.utc: argument 1 expected number"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
