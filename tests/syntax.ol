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
assert(n_fsep == 1000.12)   ## underscore ignoré dans float

var n_sci   = 6.022e23      ## notation scientifique → flottant
var n_scin  = 2e-3          ## exposant négatif
assert(1e3 == 1000)         ## exposant → 1000 (entier après repli numValue)
assert(1E3 == 1000)         ## 'E' majuscule accepté
assert(1.5e2 == 150)
assert(n_scin == 0.002)
assert(n_sci > 1e23)

var n_hex   = 0xFF          ## hexadécimal → entier
var n_oct   = 0o10          ## octal → entier
var n_bin   = 0b1010        ## binaire → entier
assert(n_hex == 255)
assert(n_oct == 8)
assert(n_bin == 10)
assert(0xDEAD_BEEF == 3735928559)  ## underscores dans hex
assert(0o7_7 == 63)                ## underscores dans octal
assert(0b1111_1111 == 255)         ## underscores dans binaire
assert(0b11111111 == 0xFF)         ## binaire == hexa
assert((0xF0 | 0x0F) == 0xFF)      ## littéraux hex avec opérateurs bits
assert(0xFFFFFFFFFFFFFFFF == -1)   ## motif de bits complet → wrapping int64

var s = "hello"             ## chaîne (immuable)
var s_concat = "hello" + ", " + "world"  ## concaténation avec +
assert(s_concat == "hello, world")
var vrai  = true            ## booléen (stocké comme entier 1)
var faux  = false           ## booléen (stocké comme entier 0)
var rien  = nil             ## valeur absente

## ── 3. Variables ─────────────────────────────────────────────────────────────
## Toute variable DOIT être déclarée avec `var` avant usage.
## Lire/affecter un nom non déclaré = erreur de compilation.
## `var` ne crée que des variables locales.

var x           ## non initialisé → nil
assert(x == nil)

var a, b = 10, 20           ## déclaration multiple
var p, q, r = 1, 2          ## r → nil (moins de valeurs que de noms)
assert(r == nil)

## affectation simple
a = 99
assert(a == 99)

## affectation multiple sur des variables DÉJÀ déclarées (sans `var`) : les valeurs sont
## distribuées comme à la déclaration, y compris depuis un appel à retours multiples.
a, b = 1, 2
assert(a == 1 and b == 2)
a, b = b, a                 ## échange : le membre droit est évalué avant d'écrire
assert(a == 2 and b == 1)

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

## variables globales : `global` déclare une variable visible dans tout le programme,
## déclarable n'importe où, lisible et modifiable depuis n'importe quelle fonction.
global gcount = 0
func bump()
    gcount += 1        ## écrit le global depuis une fonction
end
bump()
bump()
assert(gcount == 2)

global gmsg            ## sans init → nil
assert(gmsg == nil)
gmsg = "ready"
assert(gmsg == "ready")

## multi-déclaration
global ga, gb = 1, 2
assert(ga == 1 and gb == 2)

## référence en avant : fonction déclarée avant le global
func read_fwd()  return gfwd  end
global gfwd = 99
assert(read_fwd() == 99)

## locale masque le global dans sa portée
global gshadow = 100
func shadow_test()
    var gshadow = 7
    return gshadow
end
assert(shadow_test() == 7)
assert(gshadow == 100)

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

## concaténation : string + any → string
assert("x" + 1     == "x1")
assert("v=" + 3.14 == "v=3.14")
assert(42 + " !"   == "42 !")

## division entière plancher (//) et exponentiation (^)
assert(7 // 2    == 3)         ## IDIV → plancher vers -∞
assert(-7 // 2   == -4)
assert(2 ^ 8     == 256)       ## POW : INT^INT≥0 → INT (^ = puissance, modèle Lua)
assert(2.0 ^ -1  == 0.5)       ## exposant négatif → float
assert(-2 ^ 2    == -4)        ## ^ plus prioritaire que le moins unaire
assert(2 ^ 2 ^ 3 == 256)       ## associatif à droite : 2^(2^3)

## ── 5. Comparaisons ──────────────────────────────────────────────────────────

assert(1 == 1)
assert(1 <> 2)
assert(not (5 <> 5))    ## cas faux : opérandes égaux
assert(3 > 2)
assert(2 < 3)
assert(3 >= 3)
assert(not (2 >= 3))    ## cas faux : left < right
assert(2 <= 3)
assert(not (3 <= 2))    ## cas faux : left > right

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

## résultat faux → valeur numérique 0
var fa = false and true
assert(fa == 0)
var fo = false or false
assert(fo == 0)

## vérité des types — principe « le vide est faux »
assert(1    == true)
assert(0    == false)
assert(not not "x")    ## string non vide : truthy (== ne coerce pas les types)
assert(not "")         ## string vide : falsy
assert(not nil)        ## nil est falsy, mais nil <> false (types distincts)
assert(nil <> false)   ## nil et false sont des types distincts
assert(not {})         ## map vide : falsy
assert(not [])         ## array vide : falsy
assert(not not {a:1})  ## map non vide : truthy
assert(not not [1])    ## array non vide : truthy

## ── 7. Opérateurs bits ───────────────────────────────────────────────────────

assert((12 & 10)  == 8)        ## ET
assert((12 | 10)  == 14)       ## OU
assert((12 ~ 10)  == 6)        ## XOR : '~' binaire (modèle Lua)
assert(~0         == -1)       ## NOT : '~' unaire
assert((5 ~ ~0)   == -6)       ## XOR de 5 et (NOT 0) = 5 ~ -1
assert((1 << 3)   == 8)
assert((16 >> 2)  == 4)

## ── 8. If / else if / else ───────────────────────────────────────────────────

var score = 75
var grade = "F"

if score >= 90 then
    grade = "A"
elseif score >= 70 then
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
while i < 5 do
    i += 1
end
assert(i == 5)

## break
var j = 0
while true do
    j += 1
    if j >= 3 then break end
end
assert(j == 3)

## continue
var sum = 0
var k = 0
while k < 10 do
    k += 1
    if k % 2 == 0 then continue end    ## saute les pairs
    sum += k
end
assert(sum == 25)   ## 1+3+5+7+9

## ── 10. For ──────────────────────────────────────────────────────────────────

## range inclusif [1;5] → 1,2,3,4,5
var s1 = 0
for i in [1;5] do
    s1 += i
end
assert(s1 == 15)

## numérique sans step
var s2 = 0
for i = 1, 5 do
    s2 += i
end
assert(s2 == 15)

## step positif
var s3 = 0
for i = 1, 9, 2 do
    s3 += i
end
assert(s3 == 25)    ## 1+3+5+7+9

## step négatif
var s4 = 0
for i = 5, 1, -1 do
    s4 += i
end
assert(s4 == 15)

## break dans for range
var s5 = 0
for i in [1;100] do
    if i > 5 then break end
    s5 += i
end
assert(s5 == 15)

## continue dans for range
var s6 = 0
for i in [1;10] do
    if i % 2 == 0 then continue end
    s6 += i
end
assert(s6 == 25)

## range exclusif droit [1;5[ → 1,2,3,4
var s8 = 0
for i in [1;5[ do
    s8 += i
end
assert(s8 == 10)

## range avec step [1;10;2] → 1,3,5,7,9
var s9 = 0
for i in [1;10;2] do
    s9 += i
end
assert(s9 == 25)

## range first-class : stocker dans une variable
var rng = [1;5]
var s10 = 0
for i in rng do
    s10 += i
end
assert(s10 == 15)

## range exclusif gauche ]1;5[ → 2,3,4
var s11 = 0
for i in ]1;5[ do
    s11 += i
end
assert(s11 == 9)

## range semi-ouvert ]1;5] → 2,3,4,5
var s12 = 0
for i in ]1;5] do
    s12 += i
end
assert(s12 == 14)

## continue dans for k,v in map
var cm = {a: 1, b: 2, c: 3, d: 4}
var cs1 = 0
for k, v in cm do
    if v % 2 == 0 then continue end
    cs1 += v
end
assert(cs1 == 4)   ## 1+3

## continue dans for v in array
var cs2 = 0
for v in [1, 2, 3, 4, 5] do
    if v % 2 == 0 then continue end
    cs2 += v
end
assert(cs2 == 9)   ## 1+3+5

## ── 11. Fonctions ────────────────────────────────────────────────────────────

## déclaration et appel
func add(a, b)
    return a + b
end
assert(add(3, 4) == 7)

## postfix sur expression parenthésée : (expr)(args), (expr)[i], (expr).champ
assert((func(x) return x * 2 end)(21) == 42)   ## appel d'une lambda parenthésée
assert(([10, 20, 30])[2] == 20)                 ## index
assert(({a: 7}).a == 7)                         ## champ
## appel optionnel f?() : nil → rien (nil), fonction → appel, autre → erreur
assert(add?(3, 4) == 7)     ## callable → appel normal
var maybe = nil
assert(maybe?() == nil)     ## nil → pas d'appel, pas d'erreur
var cb = func(n) return n * 2 end
assert(cb?(21) == 42)       ## closure en variable
cb = nil
assert(cb?(21) == nil)
var holder = {fn: func() return "ok" end}
assert(holder["fn"]?() == "ok")  ## appel optionnel sur expression
assert(holder["absent"]?() == nil)  ## clé absente → nil → ignoré

## appel optionnel de méthode : self est injecté ; méthode absente → nil
class Box
    func init(v) self.v = v end
    func get() return self.v end
end
var bx = Box(7)
assert(bx.get?() == 7)      ## self injecté
assert(bx.missing?() == nil)## méthode absente → nil

## court-circuit : les arguments ne sont PAS évalués si non appelable
global opt_se
opt_se = 0
func opt_bump() opt_se = opt_se + 1 return opt_se end
var nf = nil
assert(nf?(opt_bump()) == nil)
assert(opt_se == 0)          ## opt_bump() jamais appelé (callee nil)
assert(bx.missing?(opt_bump()) == nil)
assert(opt_se == 0)          ## idem pour une méthode absente
assert(add?(opt_bump(), 10) == 11)  ## callable → args évalués (opt_bump→1)
assert(opt_se == 1)

## retours multiples
func minmax(a, b)
    if a < b then return a, b end
    return b, a
end
var lo, hi = minmax(7, 3)
assert(lo == 3 and hi == 7)

## les mêmes valeurs, affectées à des cibles DÉJÀ déclarées — variable, champ de map,
## élément de tableau (la distribution elle-même est éprouvée dans `regressions.ol`).
var cible = {}
var tab = [0, 0]
lo, cible.min, tab[2] = minmax(5, 1)
assert(lo == 1 and cible.min == 5 and tab[2] == nil)

## récursion
func fact(n)
    if n < 2 then return 1 end
    return n * fact(n - 1)
end
assert(fact(0) == 1)    ## cas limite : n=0 déclenche la branche n < 2
assert(fact(5) == 120)

## paramètres par défaut (constes littérales uniquement)
func greet(name, greeting = "Bonjour")
    return greeting
end
assert(greet("Alice")          == "Bonjour")
assert(greet("Bob", "Salut")   == "Salut")

## appel zéro args : param sans défaut → nil par manque d'arguments
func f_nodefault(a, b)
    return a
end
assert(f_nodefault() == nil)

## varargs purs : la fonction accepte n'importe quel nombre d'arguments
func wrap(...)
    return ...
end
var w1, w2, w3 = wrap(10, 20, 30)
assert(w1 == 10 and w2 == 20 and w3 == 30)

func passthrough(a, ...)
    return a, ...
end
var r1, r2, r3 = passthrough(1, 2, 3)
assert(r1 == 1 and r2 == 2 and r3 == 3)

## fonction sur une ligne
func double(x)  return x * 2  end
assert(double(5) == 10)

## définition sur un champ de map : `func obj.field(...)` = `obj.field = func(...)`
var handlers = {}
func handlers.greet(name)
    return "salut " + name
end
assert(handlers.greet("ollin") == "salut ollin")
func handlers.add(a, b = 5)   ## params + défaut fonctionnent aussi
    return a + b
end
assert(handlers.add(10) == 15)
assert(handlers.add(10, 20) == 30)

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

## fonctions anonymes (lambdas)
func make_counter2()
    var n = 0
    return func()
        n = n + 1
        return n
    end
end
var cx = make_counter2()
assert(cx() == 1)
assert(cx() == 2)
assert(cx() == 3)

var double = func(x)  return x * 2  end
assert(double(7) == 14)

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

## clés littérales : ident, "string" et ["string"] sont équivalents (clé = la string)
var lit = {
    a: 1,
    "a2": 2,
    ["a3"]: 3
}
assert(lit["a"]  == 1)
assert(lit["a2"] == 2)
assert(lit["a3"] == 3)

## clé calculée : [expr] utilise la VALEUR de l'expression comme clé
var kname = "calculee"
var ck = {
    kname:   1,      ## clé littérale "kname"
    [kname]: 2,      ## clé "calculee" (valeur de kname)
    [1 + 1]: "deux"  ## clé entière 2
}
assert(ck["kname"]    == 1)
assert(ck["calculee"] == 2)
assert(ck[2]          == "deux")
assert(ck["kname"] <> ck["calculee"])

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
var alias = orig          ## `ref` est un mot-clé (passage par référence) → autre nom
alias.x = 99
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

## clés : array, map, fonction
var km_arr = [1, 2]
km[km_arr] = "array"
assert(km[km_arr] == "array")

var km_map = {"a": 1}
km[km_map] = "map"
assert(km[km_map] == "map")

func km_fn()  end
km[km_fn] = "func"
assert(km[km_fn] == "func")

## itération clé+valeur
var total = 0
for k, v in {x: 1, y: 2, z: 3} do
    total += v
end
assert(total == 6)

## itération clé seule (1 variable sur map → clé)
var key_sum = 0
for k in {a: 1, b: 2, c: 3} do
    key_sum += 1   ## on compte juste les itérations
end
assert(key_sum == 3)

## for k,v dans une fonction
func sum_map_vals(m)
    var s = 0
    for k, v in m do
        s += v
    end
    return s
end
assert(sum_map_vals({x: 1, y: 2, z: 3}) == 6)

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
for v in [1, 2, 3, 4, 5] do
    s7 += v
end
assert(s7 == 15)

## itération index + valeur
for i, v in arr do
    print("{i}: {v}")
end

## sémantique référence
var arr2 = arr
arr2[1] = 0
assert(arr[1] == 0)

## ── 16. Builtins ─────────────────────────────────────────────────────────────

## print — arguments séparés par espaces, retour à la ligne
print("hello", 42, true)    ## hello 42 1

## printf — substitution POSITIONNELLE : {} auto, {N} indexé (pas d'échappement).
## {N:spec} applique un format C (spec = conversion sans le '%').
printf("{} + {} = {}", 1, 2, 3)            ## 1 + 2 = 3  (auto : 1-based)
printf("{1} et {1}", "oui")                ## oui et oui  (index 1 = 1er argument)
printf("a={1} b={2} a={1}", 10, 20)        ## a=10 b=20 a=10
printf("pi = {1:.3f}", 3.14159)            ## pi = 3.142
printf("hex = {1:04x}", 255)               ## hex = 00ff

## interpolation de chaînes : {expr} évalue l'expression ; {expr:spec} la formate.
var iname = "monde"
var ix = 42
assert("hello {iname}" == "hello monde")
assert("x={ix}" == "x=42")
assert("calc: {ix * 2 + 1}" == "calc: 85")
assert("{ix}{ix}" == "4242")
assert("pi~{3.14}" == "pi~3.14")
assert("pi={3.14159:.2f}" == "pi=3.14")            ## format : 2 décimales
assert("hex={(255):04x}" == "hex=00ff")            ## expression + format (parenthèses)
assert("pad=[{ix:5d}]" == "pad=[   42]")           ## largeur
assert(len("ac\{olade") == 8)    ## \{ = accolade littérale (1 char)
assert("{1} litteral" == "{1} litteral")           ## {N} = placeholder positionnel (1-based), littéral en interpolation

## assert — lève une exception si falsy
assert(1 + 1 == 2)
assert(true, "doit être vrai")

## time — secondes UNIX (float)
var t0 = time()
var t1 = time()
assert(t1 >= t0)

## len — taille d'une collection ou string
var la = [1, 2, 3]
assert(len(la) == 3)
assert(len("hello") == 5)
assert(len({a: 1, b: 2}) == 2)
assert(len([1;5]) == 5)

## # — sucre syntaxique pour len()
assert(#la == 3)
assert(#"hello" == 5)
assert(#{a: 1, b: 2} == 2)
assert(#[1;5] == 5)
assert(#la == len(la))

## méthodes array
assert(la.len() == len(la))
assert([10, 20, 30].len() == 3)
var nested = [[1, 2], [3, 4]]
assert(nested.len() == 2)
assert(nested[1].len() == 2)

var ma = [1, 2, 3]
ma.push(4)
assert(ma[4] == 4)
assert(ma.pop() == 4)
assert(ma.len() == 3)
ma.insert(2, 99)
assert(ma[2] == 99)
assert(ma.delete(2) == 99)
assert(ma[2] == 2)

var fifo = []
fifo.enqueue(10)
fifo.enqueue(20)
assert(fifo.dequeue() == 10)
assert(fifo.dequeue() == 20)

## méthodes de chaînes : les fonctions du module `string` s'appellent aussi SUR la chaîne,
## qui devient le premier argument. Comptage par caractère et bornes hors chaîne :
## comportement, donc `regressions.ol`.
assert("Ollin".len() == 5)
assert("Ollin".upper() == "OLLIN")
assert("OLLIN".lower() == "ollin")
assert("  bord  ".trim() == "bord")
assert("  bord  ".ltrim() == "bord  ")
assert("  bord  ".rtrim() == "  bord")
assert("abcdef".substr(2, 3) == "bcd")     ## début en 1, longueur
assert("abcdef".substr(2) == "bcdef")      ## sans longueur : jusqu'à la fin
assert("abcdef".char(1) == "a")

## la forme module et la forme méthode désignent la même fonction
assert(string.upper("Ollin") == "Ollin".upper())

## le résultat est une chaîne comme une autre : les appels se chaînent
assert("  MiXte  ".trim().lower().substr(1, 2) == "mi")

## ── 17. Import ───────────────────────────────────────────────────────────────

## import plat : les symboles du fichier sont injectés dans le scope courant
import "utils_test1"
assert(CONST == 42)

## import modulaire (fichier différent) : symboles regroupés dans une map
import "utils_test2" as u
assert(u.mul(3, 4) == 12)
assert(u.VERSION == 2)

## import circulaire : ignoré silencieusement (déjà importé)
import "utils_test1"
assert(CONST == 42)   ## toujours disponible

## ── 18. Classes ──────────────────────────────────────────────────────────────

## classe de base
class Animal
    func init(name, sound)
        self.name = name
        self.sound = sound
    end
    func speak()
        return self.name + " says " + self.sound
    end
    func __str()
        return "Animal(" + self.name + ")"
    end
end

var anm = Animal("Dog", "woof")
assert(anm.speak() == "Dog says woof")
assert(anm.name == "Dog")
assert(anm.sound == "woof")

## héritage simple
class Dog extends Animal
    func init(name)
        super.init(name, "woof")
    end
    func fetch()
        return self.name + " fetches!"
    end
    ## `super.` ne sert pas qu'au constructeur : il appelle la version parente de
    ## n'importe quelle méthode, ici redéfinie sous le même nom.
    func crier()
        return "[" + super.speak() + "]"
    end
end

var d = Dog("Rex")
assert(d.speak() == "Rex says woof")
assert(d.fetch() == "Rex fetches!")
assert(d.name == "Rex")
assert(d.crier() == "[Rex says woof]")

## héritage sans init propre (hérite du parent)
class Cat extends Animal
    func purr()
        return self.name + " purrs"
    end
end

var catw = Cat("Whiskers", "meow")
assert(catw.speak() == "Whiskers says meow")
assert(catw.purr() == "Whiskers purrs")

## méthode qui modifie self
class Counter
    func init(start)
        self.n = start
    end
    func increment()
        self.n = self.n + 1
    end
    func value()
        return self.n
    end
end

var ctr = Counter(0)
ctr.increment()
ctr.increment()
ctr.increment()
assert(ctr.value() == 3)

## méta-méthodes : un opérateur du langage par méthode. Les comparaisons dérivées
## (`>`, `>=`, `<>`) et leur symétrie sont de la sémantique → `regressions.ol`.
class Nombre
    func init(v)
        self.v = v
    end
    func __add(o)  return Nombre(self.v + o.v)  end
    func __sub(o)  return Nombre(self.v - o.v)  end
    func __mul(o)  return Nombre(self.v * o.v)  end
    func __div(o)  return Nombre(self.v / o.v)  end
    func __mod(o)  return Nombre(self.v % o.v)  end
    func __neg()   return Nombre(-self.v)  end
    func __eq(o)   return self.v == o.v  end
    func __lt(o)   return self.v < o.v  end
    func __le(o)   return self.v <= o.v  end
    func __str()   return "Nombre({self.v})"  end
end

var n10 = Nombre(10)
var n4 = Nombre(4)
assert((n10 + n4).v == 14)
assert((n10 - n4).v == 6)
assert((n10 * n4).v == 40)
assert((n10 / n4).v == 2.5)
assert((n10 % n4).v == 2)
assert((-n10).v == -10)
assert(n10 == Nombre(10))
assert(n4 < n10)
assert(n10 <= Nombre(10))
assert("{n10}" == "Nombre(10)")

## méthodes statiques (appelables sur la classe, pas de self)
class Factory
    static func zero()
        return Factory.make(0)
    end
    static func make(val)
        var obj = Factory()
        obj.val = val
        return obj
    end
    func init()
        self.val = -1
    end
    func get()
        return self.val
    end
end

var f0 = Factory.zero()
assert(f0.get() == 0)

var f5 = Factory.make(5)
assert(f5.get() == 5)

## appel via une instance : pas de self injecté
var fi = Factory()
var f7 = fi.make(7)
assert(f7.get() == 7)

print("class tests ok")

## ── 19. Constantes ───────────────────────────────────────────────────────────

## 'const' : locale immuable, initialisation obligatoire
const PI = 3.14159
const MAX = 100
assert(PI  == 3.14159)
assert(MAX == 100)

## conste dans une fonction
func circle_area(r)
    const TWO_PI = 2 * PI
    return TWO_PI * r * r
end
assert(circle_area(1) == 2 * PI)

## conste capturée en lecture seule par une closure
const BASE = 10
func with_base(x)  return BASE + x  end
assert(with_base(5) == 15)

## Ce que le moteur doit REFUSER (const non initialisée, écriture sur une constante,
## redéclaration d'une locale ou d'une globale) est vérifié par `tests/test_errors.sh`,
## avec le message rendu. Ne pas le recopier ici en commentaire : deux descriptions du
## même refus divergent tôt ou tard.

## ── 21. Module math ──────────────────────────────────────────────────────────

## constantes
assert(math.PI  == 3.141592653589793)
assert(math.TAU == 6.283185307179586)
assert(math.TAU == 2 * math.PI)

## abs
assert(math.abs(5)    == 5)
assert(math.abs(-5)   == 5)
assert(math.abs(0)    == 0)
assert(math.abs(-3.5) == 3.5)

## sign
assert(math.sign(10)   == 1)
assert(math.sign(-10)  == -1)
assert(math.sign(0)    == 0)
assert(math.sign(2.5)  == 1)
assert(math.sign(-2.5) == -1)

## floor / ceil
assert(math.floor(2.9)  == 2)
assert(math.floor(-2.1) == -3)
assert(math.ceil(2.1)   == 3)
assert(math.ceil(-2.9)  == -2)

## sqrt
assert(math.sqrt(4)   == 2)
assert(math.sqrt(9)   == 3)
assert(math.sqrt(2.0) > 1.41 and math.sqrt(2.0) < 1.42)

## sin / cos
assert(math.sin(0) == 0)
assert(math.cos(0) == 1)
assert(math.sin(math.PI) > -0.001 and math.sin(math.PI) < 0.001)

## rand — valeur dans [0, 1)
var rnd = math.rand()
assert(rnd >= 0 and rnd < 1)

## noise — bruit de Perlin fractal (fBm), 1/2/3 dimensions → [0, 1]
var nz1 = math.noise(0.5)
assert(nz1 >= 0 and nz1 <= 1)
var nz2 = math.noise(0.5, 1.5)
assert(nz2 >= 0 and nz2 <= 1)
var nz3 = math.noise(0.5, 1.5, 2.5)
assert(nz3 >= 0 and nz3 <= 1)
## déterministe : même entrée → même sortie
assert(math.noise(3.14) == math.noise(3.14))
## noiseSeed : reproductible après re-seed identique
math.noiseSeed(42)
var na = math.noise(1.7)
math.noiseSeed(42)
assert(math.noise(1.7) == na)
## graines différentes → bruit différent
math.noiseSeed(1)
var nb = math.noise(1.7)
math.noiseSeed(2)
assert(math.noise(1.7) <> nb)

## ── 22. Switch ───────────────────────────────────────────────────────────────

## cas de base — valeur entière
var sw_r = 0
switch 2
    case 1
        sw_r = 1
    case 2
        sw_r = 2
    case 3
        sw_r = 3
    else
        sw_r = 99
end
assert(sw_r == 2)

## else déclenché
switch 42
    case 1
        sw_r = 1
    else
        sw_r = 99
end
assert(sw_r == 99)

## sans else — aucun case ne matche, rien ne s'exécute
sw_r = 0
switch 7
    case 1
        sw_r = 1
    case 2
        sw_r = 2
end
assert(sw_r == 0)

## valeurs multiples par case
switch "b"
    case "a", "b"
        sw_r = 1
    case "c"
        sw_r = 2
end
assert(sw_r == 1)

## switch sur string — premier case
switch "hello"
    case "hello"
        sw_r = 10
    case "world"
        sw_r = 20
end
assert(sw_r == 10)

## switch dans une fonction
func sw_func(n)
    switch n
        case 0
            return "zero"
        case 1, 2
            return "un ou deux"
        else
            return "autre"
    end
end
assert(sw_func(0) == "zero")
assert(sw_func(1) == "un ou deux")
assert(sw_func(2) == "un ou deux")
assert(sw_func(5) == "autre")

## ── 23. Module graphics (Raylib) ─────────────────────────────────────────────
##
## Disponible en natif comme en WASM (le playground l'utilise). Le build natif par
## DÉFAUT emploie le stub : `graphics` y vaut nil. Exemples : docs/samples/.
##
##   graphics.canvas(800, 600, "Titre")   ## ouvre une fenêtre
##   func draw()                          ## appelée à chaque frame
##       graphics.clear(colors.BLACK)
##       graphics.stroke(colors.RED)      ## style : état courant
##       graphics.line(x1, y1, x2, y2)    ## géométrie : arguments
##   end
##
## RÈGLE du module : la géométrie passe par les ARGUMENTS, le style vient de
## l'ÉTAT courant (fill, stroke, strokeSize, fontSize, rectMode, spriteMode). Aucune primitive de dessin
## ne prend de couleur ni de taille en argument.
##
## Couleurs prédéfinies : module `colors` (colors.BLACK, colors.WHITE, colors.RED…)
## Couleurs personnalisées : Color(r, g, b[, a]) avec des composantes de 0 à 1
##   (un entier empaqueté ne marche PAS : les valeurs sont bornées à 1 → blanc)
## FPS : graphics.fps() → entier
## Texte : graphics.text(text, x, y) — couleur de stroke (on écrit au stylo)
##   graphics.fontSize(n) → taille de police ; accepte une valeur fractionnaire,
##   sans minimum, remise à 18 à chaque frame
## Ancrage des rectangles : graphics.rectMode("corner" | "center") — "corner" (défaut,
##   x,y = coin supérieur gauche) est remis à chaque frame ; en "center", x,y = centre
## Ancrage de circle/ellipse/arc : graphics.ellipseMode("center" | "corner") — le
##   défaut est "center" (ces primitives sont centrées) ; en "corner", la boîte de
##   référence d'arc est celle de l'ellipse entière, pas du secteur tracé
## Ancrage des images : graphics.spriteMode("corner" | "center") — vaut pour
##   graphics.sprite ET image.draw ; le décalage porte sur la taille affichée

## ── 24. Méthodes d'instance array (fonctions d'ordre supérieur) ──────────────

var am_doubled = [1, 2, 3].map(func(x) return x * 2 end)
assert(am_doubled.len() == 3)
assert(am_doubled[1] == 2 and am_doubled[2] == 4 and am_doubled[3] == 6)

var am_evens = [1, 2, 3, 4, 5].filter(func(x) return x % 2 == 0 end)
assert(am_evens.len() == 2)
assert(am_evens[1] == 2 and am_evens[2] == 4)

var am_sum = [1, 2, 3, 4].reduce(func(acc, x) return acc + x end, 0)
assert(am_sum == 10)

var am_product = [1, 2, 3, 4].reduce(func(acc, x) return acc * x end, 1)
assert(am_product == 24)

var am_idx = ["a", "b"].map(func(v, i) return i end)
assert(am_idx[1] == 1 and am_idx[2] == 2)

var am_sorted = [3, 1, 2].sort()
assert(am_sorted[1] == 1 and am_sorted[2] == 2 and am_sorted[3] == 3)
var am_mixed = [2.5, nil, "z", 1]
am_mixed.sort()
assert(am_mixed[1] == nil and am_mixed[2] == 1 and am_mixed[3] == 2.5 and am_mixed[4] == "z")

## ── 25. Bloc do...end (portée lexicale) ───────────────────────────────────────
var do_x = 0
do
    var do_tmp = 42
    do_x = do_tmp + 1
end
assert(do_x == 43)

var do_fns = []
do
    var do_i = 99
    do_fns.push(func() return do_i end)
end
assert(do_fns[1]() == 99)

do
    var do_a = 1
    do
        var do_b = do_a + 1
        assert(do_b == 2)
    end
end

## ── 26. enum (constantes nommées, map gelée) ─────────────────────────────────
## Sans valeur : le premier vaut 1, chacun suit à +1.
enum Couleur ROUGE, VERT, BLEU end
assert(Couleur.ROUGE == 1 and Couleur.VERT == 2 and Couleur.BLEU == 3)

## Un littéral entier fixe la valeur ; le compteur repart à valeur+1.
enum Etat REPOS = 0, MARCHE, SAUT = 10, CHUTE end
assert(Etat.REPOS == 0 and Etat.MARCHE == 1 and Etat.SAUT == 10 and Etat.CHUTE == 11)

## Toute expression est acceptée comme valeur, mais ne déplace pas le compteur.
enum Mixte A, B = "texte", C end
assert(Mixte.A == 1 and Mixte.B == "texte" and Mixte.C == 2)

## En lecture, un enum est une map : len et itération.
assert(#Couleur == 3)
var enum_somme = 0
for k, v in Couleur do
    enum_somme = enum_somme + v
end
assert(enum_somme == 6)

## Toute écriture est refusée — ici par un alias, donc à l'exécution.
var enum_alias = Couleur
var enum_bloque = false
try
    enum_alias.ROUGE = 9
catch e
    enum_bloque = true
end
assert(enum_bloque and Couleur.ROUGE == 1)

## Déclaration dans une map existante : enum a.b
global enumCfg = {}
enum enumCfg.mode PLEIN, FENETRE end
assert(enumCfg.mode.PLEIN == 1 and enumCfg.mode.FENETRE == 2)

## ── 27. ref (passage par référence) ──────────────────────────────────────────
## `ref x` donne à une fonction le moyen de LIRE et d'ÉCRIRE la variable x.
## La cible reste une variable ordinaire : on la lit et on l'écrit normalement.
global refCible = 1
var refLocale = "a"
global refObj = {champ: 10}

func refEcrire(r, v)
    r.set(v)          ## écriture à travers la référence
end
func refLire(r)
    return r.get()
end

assert(refLire(ref refCible) == 1)
refEcrire(ref refCible, 5)
assert(refCible == 5)         ## la variable elle-même a changé

refEcrire(ref refLocale, "b")    ## une LOCALE est référençable (upvalue)
assert(refLocale == "b")

refEcrire(ref refObj.champ, 20)  ## un champ d'objet aussi
assert(refObj.champ == 20)

## Une référence est une valeur : stockable et transmissible.
var refStock = ref refCible
refStock.set(7)
assert(refCible == 7)

## ── 28. Module ui (widgets dessinés par le moteur) ────────────────────────────
## Boutons et cases à cocher en pile dans le coin haut droit de la zone de tracé.
## Un widget se déclare UNE fois ; le moteur le dessine et le teste chaque frame.
##
##   ui.button(libellé, fonction)                       → appelée à chaque clic
##   ui.checkbox(libellé, ref variable [, surChange])   → écrit true/false dedans
##   ui.slider(libellé, ref v, min, max [, défaut] [, surChange])
##                                                      → valeur numérique réglable
##   ui.clear()                                         → retire tous les widgets
##
## Les widgets peuvent être rangés dans des MENUS. Un seul menu est affiché à la
## fois ; un sous-menu s'affiche comme une ligne cliquable, et une ligne « < »
## remonte d'un niveau.
##
##   var m = ui.menu(libellé)     → menu (à la racine, ou m.menu(...) = sous-menu)
##   m.button / m.checkbox        → même déclaration, rangée dans ce menu
##   ui.show(m)                   → remplace le menu global affiché (nil = racine)
##   ui.back()                    → remonte d'un niveau ; ui.current() = menu affiché
##   ui.open([m]) / ui.close() / ui.toggle()
##                                → déplie / replie l'interface (FERMÉE au démarrage :
##                                  réduite à une poignée dans le coin)
##   m.open()                     → descend dans m (comme un clic sur sa ligne)
##   h.remove() / m.clear()       → retire un élément / vide un menu
##
## La case est liée par RÉFÉRENCE : l'état initial est lu dans la variable, chaque
## clic y écrit, et le programme lit la variable normalement. surChange(nouvelEtat)
## est appelée après le changement si elle est fournie.
##
## Un clic sur un widget n'est PAS transmis à mouse.pressed ; un clic ailleurs l'est.
## Sans zone graphique, déclarer un widget ne fait rien — mais les arguments sont
## vérifiés (label chaîne, fonction appelable, référence obligatoire).
global uiFlag = true
func uiAction() end
ui.button("Action", uiAction)
ui.checkbox("Option", ref uiFlag)

## Un slider initialise la variable liée si elle vaut nil (défaut, sinon min).
global uiVal = nil
ui.slider("Taille", ref uiVal, 0, 1, 0.25)
assert(uiVal == 0.25)
global uiVal2 = 7
ui.slider("Autre", ref uiVal2, 1, 10)
assert(uiVal2 == 7)

var uiMenu = ui.menu("Réglages")
uiMenu.checkbox("Option", ref uiFlag)
var uiSous = uiMenu.menu("Affichage")
uiSous.button("Action", uiAction)
uiSous.slider("Zoom", ref uiVal, 0, 2)
ui.show(uiMenu)
uiSous.open()
ui.back()
uiSous.remove()
uiMenu.clear()
ui.show(nil)
ui.open()
ui.toggle()
ui.close()
ui.clear()
