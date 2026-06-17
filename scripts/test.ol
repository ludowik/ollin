### test.ol — tests (Claude)
    Couvre toutes les constructions de syntax.ol
###

## ── strings ───────────────────────────────────────────────────────────────────
assert("hello" == "hello", "string literal ==")

## ── arithmétique ──────────────────────────────────────────────────────────────
var x = 2 + 3 * 4
assert(x == 14, "priorité opérateurs")

var a, b = 10, 3
assert(a - b == 7, "soustraction")

## ── déclaration multiple ──────────────────────────────────────────────────────
var p, q = 6, 7
assert(p == 6, "p == 6")
assert(q == 7, "q == 7")

## ── booleans ──────────────────────────────────────────────────────────────────
var vrai = true
var faux = false
assert(vrai == 1, "true == 1")
assert(faux == 0, "false == 0")

## ── comparaisons ──────────────────────────────────────────────────────────────
var n = 5
assert(n > 3,  "n > 3")
assert(n < 10, "n < 10")
assert(n <> 4, "n <> 4")
assert(n <> 6, "n <> 6")
var neq = false
if n <> 5 then neq = true end
assert(neq == false, "n <> 5 faux")
assert(n >= 5, "n >= 5")
assert(n >= 4, "n >= 4")
assert(n <= 5, "n <= 5")
assert(n <= 6, "n <= 6")
var no = false
if n >= 6 then no = true end
assert(no == false, "n >= 6 faux")
if n <= 4 then no = true end
assert(no == false, "n <= 4 faux")

var c = 2
assert(c == 2, "c == 2")

var s1, s2 = "hello", "hello"
assert(s1 == s2, "string ==")

## ── if then end ───────────────────────────────────────────────────────────────
var branch = 0
if faux then
    branch += 1
end
assert(branch == 0, "if false → non exécuté")

if vrai then
    branch += 1
end
assert(branch == 1, "if true → exécuté")

## ── else if / else ────────────────────────────────────────────────────────────
var score = 75
var score_branch = 0
if score > 90 then
    score_branch += 1
else if score > 70 then
    score_branch += 2
else if score > 50 then
    score_branch += 3
else
    score_branch += 4
end
assert(score_branch == 2, "else if branch correcte")

var z = 0
var z_branch = 0
if z == 1 then
    z_branch += 1
else if z == 2 then
    z_branch += 2
else
    z_branch += 3
end
assert(z_branch == 3, "else branch correcte")

## ── while + break ─────────────────────────────────────────────────────────────
var i = 0
while vrai
    i += 1
    if i > 4 then break end
end
assert(i == 5, "while + break")

## ── while avec condition ──────────────────────────────────────────────────────
var sum = 0
var k = 1
while k < 10
    sum += k
    k += 1
end
assert(sum == 45, "somme 1..9")

## ── time ──────────────────────────────────────────────────────────────────────
var t = time()
assert(t > 0, "time() > 0")

## ── try/catch/throw → catch exécuté ──────────────────────────────────────────
var try1 = 0
try
    try1 += 1
    throw "oulala"
    try1 += 10
catch err
    assert(err == "oulala", "valeur throwée")
    try1 += 2
else
    try1 += 100
end
assert(try1 == 3, "try+catch exécutés")

## ── try sans throw → else exécuté ────────────────────────────────────────────
var try2 = 0
try
    try2 += 1
catch err
    try2 += 100
else
    try2 += 2
end
assert(try2 == 3, "try sans throw → else")

## ── try vide, catch vide, sans else ──────────────────────────────────────────
try
catch err
end

## ── printf format ────────────────────────────────────────────────────────────
printf("{} + {} = {}", 1, 2, 3)        ## 1 + 2 = 3
printf("a={0} b={1} a={0}", 10, 20)    ## a=10 b=20 a=10

## ── fonctions ─────────────────────────────────────────────────────────────────

func add(a, b)
    return a + b
end

func max2(a, b)
    if a > b then
        return a
    else
        return b
    end
end

func swap(a, b)
    return b, a
end

func sum_varargs(...)
    var s = 0
    var i = 0
    while i < 3
        i += 1
    end
    return ...
end

assert(add(3, 4) == 7, "add(3,4)")
assert(add(0, 0) == 0, "add(0,0)")
assert(max2(5, 3) == 5, "max2(5,3)")
assert(max2(2, 9) == 9, "max2(2,9)")

var x, y = swap(10, 20)
assert(x == 20, "swap x")
assert(y == 10, "swap y")

## récursion
func fact(n)
    if n < 2 then
        return 1
    end
    return n * fact(n - 1)
end

assert(fact(0) == 1, "fact(0)")
assert(fact(1) == 1, "fact(1)")
assert(fact(5) == 120, "fact(5)")

## varargs passthrough
func passthrough(a, ...)
    return a, ...
end

var r1, r2, r3 = passthrough(1, 2, 3)
assert(r1 == 1, "varargs r1")
assert(r2 == 2, "varargs r2")
assert(r3 == 3, "varargs r3")

## ── séparateurs de milliers ───────────────────────────────────────────────────
assert(1000.12 == 1_000.12, "underscore float")
assert(1000000 == 1_000_000, "underscore int")

## ── nil ───────────────────────────────────────────────────────────────────────
var undef
assert(undef == nil, "var sans valeur → nil")
assert(nil == nil, "nil == nil")

## ── plain assignment ──────────────────────────────────────────────────────────
var pa = 1
pa = 42
assert(pa == 42, "plain assign")

## ── compound assignments ──────────────────────────────────────────────────────
var ca = 10
ca -= 3
assert(ca == 7, "-=")
ca *= 2
assert(ca == 14, "*=")
ca /= 7
assert(ca == 2, "/=")
ca %= 3
assert(ca == 2, "%=")

## ── modulo ────────────────────────────────────────────────────────────────────
assert(10 % 3 == 1, "10 % 3")
assert(7 % 7 == 0, "7 % 7")

## ── unary minus ───────────────────────────────────────────────────────────────
var neg = -5
assert(neg == -5 + 0, "unary minus var")
assert(-3 + 3 == 0, "-3 + 3")

## ── leading decimal ──────────────────────────────────────────────────────────
assert(.5 + .5 == 1, ".5 literal")

## ── not ──────────────────────────────────────────────────────────────────────
assert(not false,      "not false")
assert(not false == 1, "not false == 1")
assert(not true  == 0, "not true == 0")
assert(not nil   == 1, "not nil")
assert(not 0     == 1, "not 0")
assert(not ""    == 1, "not vide")

## ── or / and ─────────────────────────────────────────────────────────────────
assert(true or false, "true or false")
assert(false or true, "false or true")
assert(true and true, "true and true")
var fa = false and true
assert(fa == 0, "false and true == 0")
var fo = false or false
assert(fo == 0, "false or false == 0")
assert(true or false and false, "or/and precedence")

## ── string truthy/falsy ───────────────────────────────────────────────────────
assert("non vide" == true, "non-empty string == true")
assert("" == false, "empty string == false")

## ── default parameter values ─────────────────────────────────────────────────
func f2(arg1, arg2=1)
    assert(arg1 == nil, "arg1 nil par défaut")
    assert(arg2 == 1,   "arg2 défaut = 1")
end
f2()
f2(nil)

func fwith_defaults(x=10, y=20)
    return x + y
end
assert(fwith_defaults() == 30, "defaults x+y")
assert(fwith_defaults(5) == 25, "partial default")
assert(fwith_defaults(5, 5) == 10, "no default")

## ── for in (range) ──────────────────────────────────────────────────────────
var for_sum = 0
for i in [1;10]
    for_sum += i
end
assert(for_sum == 55, "for in [1;10]")

## ── for numérique sans step ──────────────────────────────────────────────────
var for_sum2 = 0
for j=1,10
    for_sum2 += j
end
assert(for_sum2 == 55, "for j=1,10")

## ── for avec step positif ────────────────────────────────────────────────────
var for_step = 0
for k=1,10,2
    for_step += k
end
assert(for_step == 25, "for k=1,10,2 (1+3+5+7+9)")

## ── for avec step négatif ────────────────────────────────────────────────────
var for_rev = 0
for m=5,1,-1
    for_rev += m
end
assert(for_rev == 15, "for m=5,1,-1 (5+4+3+2+1)")

## ── for break ────────────────────────────────────────────────────────────────
var for_break = 0
for i in [1;100]
    if i > 5 then break end
    for_break += i
end
assert(for_break == 15, "for break at 5")

## ── map : création et accès ──────────────────────────────────────────────────
var m = {"a": 1, "b": 2}
assert(m["a"] == 1, "map get a")
assert(m["b"] == 2, "map get b")
assert(m["x"] == nil, "clé absente → nil")

## ── map : set index ──────────────────────────────────────────────────────────
m["c"] = 3
assert(m["c"] == 3, "map set c")

## ── map : compound assignment ────────────────────────────────────────────────
m["a"] += 10
assert(m["a"] == 11, "map compound +=")
m["b"] *= 3
assert(m["b"] == 6, "map compound *=")

## ── map : map vide ───────────────────────────────────────────────────────────
var empty = {}
assert(empty["x"] == nil, "map vide → nil")
empty["x"] = 42
assert(empty["x"] == 42, "map vide → set")

## ── map : isFalsy ────────────────────────────────────────────────────────────
assert(not (not {}) == 1, "map is truthy")

## ── entiers natifs ───────────────────────────────────────────────────────────
assert(1 + 2 == 3, "int + int → int")
assert(10 - 3 == 7, "int - int → int")
assert(6 * 7 == 42, "int * int → int")
assert(10 % 3 == 1, "int % int → int")
var fdiv = 7 / 2
assert(fdiv == 3.5, "int / int → float")

## ── map : multi-lignes et clés identifiants ─────────────────────────────────
var ml = {
    "x": 10,
    y: 20,
    z: 30
}
assert(ml["x"] == 10, "multiline map x")
assert(ml["y"] == 20, "multiline map ident key y")
assert(ml["z"] == 30, "multiline map ident key z")

## ── map : accès par point (lecture) ─────────────────────────────────────────
var dot = {"a": 1, "b": 2}
assert(dot.a == 1, "dot read a")
assert(dot.b == 2, "dot read b")
assert(dot.x == nil, "dot read absent → nil")

## ── map : affectation par point ──────────────────────────────────────────────
dot.c = 99
assert(dot["c"] == 99, "dot assign c")
assert(dot.c == 99, "dot read c")
dot.a += 9
assert(dot.a == 10, "dot compound +=")
dot.a *= 2
assert(dot.a == 20, "dot compound *=")

## ── for k,v in map ───────────────────────────────────────────────────────────
var itm = {"a": 1, "b": 2, "c": 3}
var for_map_sum = 0
for k, v in itm
    for_map_sum += v
end
assert(for_map_sum == 6, "for k,v sum values")

## for k,v inside a function
func sum_map(m)
    var s = 0
    for k, v in m
        s += v
    end
    return s
end
assert(sum_map(itm) == 6, "for k,v in function")

## ── closures / upvalues ──────────────────────────────────────────────────────

## top-level var accessible depuis une fonction (upvalue)
var upv_counter = 0
func upv_inc()
    upv_counter += 1
end
upv_inc()
upv_inc()
upv_inc()
assert(upv_counter == 3, "upvalue counter")

## deux fonctions partagent le même upvalue
var upv_shared = 10
func upv_add(x)  upv_shared += x  end
func upv_get()   return upv_shared end
upv_add(5)
assert(upv_get() == 15, "upvalue partagé")

## fonction récursive capturant un upvalue
var upv_factor = 2
func upv_fact(n)
    if n < 1 then return upv_factor end
    return n * upv_fact(n - 1)
end
assert(upv_fact(3) == 6 * upv_factor, "closure récursive")

## ── clés de map : tous les types ─────────────────────────────────────────────
var km = {}

km[nil] = "nil"
assert(km[nil] == "nil", "clé nil")

km[42] = "int"
assert(km[42] == "int", "clé int")

km[3.14] = "float"
assert(km[3.14] == "float", "clé float")

## cross-type int/float
km[1] = "one"
assert(km[1.0] == "one", "clé int == clé float")

km["str"] = "string"
assert(km["str"] == "string", "clé string")

km[true]  = "vrai"
km[false] = "faux"
assert(km[true]  == "vrai", "clé true")
assert(km[false] == "faux", "clé false")

var km_arr = [1, 2]
km[km_arr] = "array"
assert(km[km_arr] == "array", "clé array")

var km_map = {"a": 1}
km[km_map] = "map"
assert(km[km_map] == "map", "clé map")

func km_fn() end
km[km_fn] = "func"
assert(km[km_fn] == "func", "clé function")

## ── benchmark : boucle incrémentale 1 000 000 itérations ────────────────────
var t0 = time()
var count = 0
while count < 1_000_000
    count += 1
end
var t1 = time()
printf("benchmark: {} s", t1 - t0)

