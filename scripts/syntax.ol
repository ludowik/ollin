### syntax.ol — source de vérité du langage Ollin
    Couvre toutes les constructions dans l'ordre pédagogique.
###

## ── 1. Commentaires ──────────────────────────────────────────────────────────

## commentaire de fin de ligne

###
commentaire
multi-lignes
###

## ── 2. Types & littéraux ─────────────────────────────────────────────────────

var n_int   = 42            ## entier (int64)
var n_float = 3.14          ## flottant (double)
var n_lead  = .5            ## décimal sans zéro initial
var n_sep   = 1_000_000     ## underscores ignorés
var n_fsep  = 1_000.12

var s = "hello"             ## chaîne (immuable)
var s2 = "hello" + ", " + "world"  ## concaténation avec +
assert(s2 == "hello, world")
var vrai  = true            ## booléen (stocké comme entier 1)
var faux  = false           ## booléen (stocké comme entier 0)
var rien  = nil             ## valeur absente

## ── 3. Variables ─────────────────────────────────────────────────────────────

var x           ## non initialisé → nil
assert(x == nil)

var a, b = 10, 20           ## déclaration multiple
var p, q, r = 1, 2          ## r → nil (moins de valeurs que de noms)
assert(r == nil)

## affectation simple
a = 99
assert(a == 99)

## affectations composées
var c = 10
c += 3
assert(c == 13)
c -= 5
assert(c == 8)
c *= 2
assert(c == 16)
c /= 4
assert(c == 4.0)
c = 10
c %= 3
assert(c == 1)

## ── 4. Arithmétique ──────────────────────────────────────────────────────────

assert(2 + 3   == 5)
assert(10 - 4  == 6)
assert(3 * 7   == 21)
assert(7 / 2   == 3.5)      ## division → toujours float
assert(10 % 3  == 1)
assert(-5 + 5  == 0)        ## négation unaire
assert(2 + 3 * 4 == 14)     ## priorité : * avant +

## INT op INT → INT ; INT op FLOAT → FLOAT
assert(1 + 2     == 3)
assert(1 + 2.0   == 3.0)

## ── 5. Comparaisons ──────────────────────────────────────────────────────────

assert(1 == 1)
assert(1 <> 2)
assert(3 > 2)
assert(2 < 3)
assert(3 >= 3)
assert(2 <= 3)

## cross-type numérique
assert(1 == 1.0)
assert(1.0 <> 2)

## ── 6. Logique ───────────────────────────────────────────────────────────────

assert(true  or  false)
assert(false or  true)
assert(true  and true)
assert(not false)
assert(not nil   == 1)
assert(not 0     == 1)
assert(not ""    == 1)

## précédence : not > and > or
assert(true or false and false)     ## true or (false and false)

## vérité des types
assert(1    == true)
assert(0    == false)
assert("x" == true)    ## string non vide : truthy == 1
assert(""  == false)   ## string vide : falsy == 0
assert(not nil)        ## nil est falsy, mais nil <> false (types distincts)

## ── 7. Opérateurs bits ───────────────────────────────────────────────────────

assert((12 & 10)  == 8)
assert((12 | 10)  == 14)
assert((12 ^ 10)  == 6)
assert(~0         == -1)
assert((1 << 3)   == 8)
assert((16 >> 2)  == 4)

## ── 8. If / else if / else ───────────────────────────────────────────────────

var score = 75
var grade = "F"

if score >= 90 then
    grade = "A"
else if score >= 70 then
    grade = "C"
else
    grade = "F"
end
assert(grade == "C")

## if sur une ligne
var ok = false
if true then ok = true end
assert(ok)

## ── 9. While ─────────────────────────────────────────────────────────────────

var i = 0
while i < 5
    i += 1
end
assert(i == 5)

## break
var j = 0
while true
    j += 1
    if j >= 3 then break end
end
assert(j == 3)

## continue
var sum = 0
var k = 0
while k < 10
    k += 1
    if k % 2 == 0 then continue end    ## saute les pairs
    sum += k
end
assert(sum == 25)   ## 1+3+5+7+9

## ── 10. For ──────────────────────────────────────────────────────────────────

## range inclusif
var s1 = 0
for i in 1..5
    s1 += i
end
assert(s1 == 15)

## numérique sans step
var s2 = 0
for i = 1, 5
    s2 += i
end
assert(s2 == 15)

## step positif
var s3 = 0
for i = 1, 9, 2
    s3 += i
end
assert(s3 == 25)    ## 1+3+5+7+9

## step négatif
var s4 = 0
for i = 5, 1, -1
    s4 += i
end
assert(s4 == 15)

## break dans for
var s5 = 0
for i in 1..100
    if i > 5 then break end
    s5 += i
end
assert(s5 == 15)

## continue dans for
var s6 = 0
for i in 1..10
    if i % 2 == 0 then continue end
    s6 += i
end
assert(s6 == 25)

## ── 11. Fonctions ────────────────────────────────────────────────────────────

## déclaration et appel
func add(a, b)
    return a + b
end
assert(add(3, 4) == 7)

## retours multiples
func minmax(a, b)
    if a < b then return a, b end
    return b, a
end
var lo, hi = minmax(7, 3)
assert(lo == 3 and hi == 7)

## récursion
func fact(n)
    if n < 2 then return 1 end
    return n * fact(n - 1)
end
assert(fact(5) == 120)

## paramètres par défaut (constantes littérales uniquement)
func greet(name, greeting = "Bonjour")
    return greeting
end
assert(greet("Alice")          == "Bonjour")
assert(greet("Bob", "Salut")   == "Salut")

## varargs
func sum_all(...)
    var s = 0
    var i = 1
    while i <= 3
        s += 1
        i += 1
    end
    return ...
end

func passthrough(a, ...)
    return a, ...
end
var r1, r2, r3 = passthrough(1, 2, 3)
assert(r1 == 1 and r2 == 2 and r3 == 3)

## fonction sur une ligne
func double(x)  return x * 2  end
assert(double(5) == 10)

## ── 12. Closures ─────────────────────────────────────────────────────────────

## upvalue : variable de la portée englobante
var counter = 0
func inc()  counter += 1  end
inc()  inc()  inc()
assert(counter == 3)

## fabrique : chaque appel crée un état indépendant
func make_counter()
    var n = 0
    func next()
        n += 1
        return n
    end
    return next
end

var c1 = make_counter()
var c2 = make_counter()
assert(c1() == 1)
assert(c1() == 2)
assert(c2() == 1)   ## état indépendant

## fonctions imbriquées (non exportées dans les globaux)
func make_adder(x)
    func add(y)  return x + y  end
    return add
end
var add5 = make_adder(5)
assert(add5(3) == 8)

## ── 13. Gestion d'erreurs ────────────────────────────────────────────────────

## throw + catch
var caught = nil
try
    throw "oops"
catch err
    caught = err
end
assert(caught == "oops")

## else exécuté si pas d'exception
var ok2 = false
try
    var dummy = 1
catch err
    ok2 = false
else
    ok2 = true
end
assert(ok2)

## throw de n'importe quel type
try
    throw {code: 42, msg: "erreur"}
catch e
    assert(e["code"] == 42)
end

## try / catch / end vides
try
catch err
end

## ── 14. Maps ─────────────────────────────────────────────────────────────────

## création
var vide = {}
var m = {
    "a": 1,
    b:   2,         ## clé identifiant (sans guillemets)
    c:   {}         ## valeur map imbriquée
}

## lecture : crochets ou point
assert(m["a"] == 1)
assert(m.b    == 2)
assert(m["x"] == nil)   ## clé absente → nil
assert(m.x    == nil)

## écriture
m["d"] = 4
m.e    = 5
assert(m["d"] == 4)
assert(m.e    == 5)

## affectation composée
m["a"] += 10
m.b    *= 3
assert(m["a"] == 11)
assert(m.b    == 6)

## map imbriquée
var scene = {camera: {fov: 60}}
assert(scene["camera"]["fov"] == 60)
assert(scene.camera.fov       == 60)

## sémantique référence
var orig = {x: 1}
var ref  = orig
ref.x = 99
assert(orig.x == 99)

## clés de tout type (via crochets)
var km = {}
km[nil]   = "nil"
km[42]    = "int"
km[3.14]  = "float"
km[true]  = "vrai"
km[false] = "faux"
assert(km[nil]   == "nil")
assert(km[42]    == "int")
assert(km[1.0]   == km[1])     ## int == float comme clé (si même valeur numérique)

## itération
var total = 0
for k, v in {x: 1, y: 2, z: 3}
    total += v
end
assert(total == 6)

## ── 15. Arrays ───────────────────────────────────────────────────────────────

## création
var arr = [10, 20, 30]
var vide2 = []

## lecture / écriture (indexé à 1)
assert(arr[1] == 10)
assert(arr[4] == nil)   ## hors bounds → nil
arr[2] = 99
arr[3] += 1
assert(arr[2] == 99)
assert(arr[3] == 31)

## grossit automatiquement
var a2 = []
a2[3] = "x"
assert(a2[1] == nil)
assert(a2[3] == "x")

## itération valeurs seules
var s7 = 0
for v in [1, 2, 3, 4, 5]
    s7 += v
end
assert(s7 == 15)

## itération index + valeur
for i, v in arr
    printf("{}: {}", i, v)
end

## sémantique référence
var arr2 = arr
arr2[1] = 0
assert(arr[1] == 0)

## ── 16. Builtins ─────────────────────────────────────────────────────────────

## print — arguments séparés par espaces, retour à la ligne
print("hello", 42, true)    ## hello 42 1

## printf — substitution positionnelle ou indexée
printf("{} + {} = {}", 1, 2, 3)         ## 1 + 2 = 3
printf("{0} et {0}", "oui")             ## oui et oui

## assert — lève une exception si falsy
assert(1 + 1 == 2)
assert(true, "doit être vrai")

## time — secondes UNIX (float)
var t0 = time()
var t1 = time()
assert(t1 >= t0)
