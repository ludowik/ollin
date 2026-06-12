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
assert(n > 3, "n > 3")
assert(n < 10, "n < 10")

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

## ── benchmark : boucle incrémentale 1 000 000 itérations ────────────────────
var t0 = time()
var count = 0
while count < 1000000
    count += 1
end
var t1 = time()
printf("benchmark: {} s", t1 - t0)
