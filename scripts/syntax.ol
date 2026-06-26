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

var n_hex   = 0xFF          ## hexadécimal → entier
var n_oct   = 0o10          ## octal → entier
assert(n_hex == 255)
assert(n_oct == 8)
assert(0xDEAD_BEEF == 3735928559)  ## underscores dans hex
assert(0o7_7 == 63)                ## underscores dans octal
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

## division entière plancher (//) et exponentiation (**)
assert(7 // 2    == 3)         ## IDIV → plancher vers -∞
assert(-7 // 2   == -4)
assert(2 ** 8    == 256)       ## POW : INT**INT≥0 → INT
assert(2.0 ** -1 == 0.5)       ## exposant négatif → float

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

## vérité des types
assert(1    == true)
assert(0    == false)
assert(not not "x")    ## string non vide : truthy (== ne coerce pas les types)
assert(not "")         ## string vide : falsy
assert(not nil)        ## nil est falsy, mais nil <> false (types distincts)
assert(nil <> false)   ## nil et false sont des types distincts

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
printf("a={0} b={1} a={0}", 10, 20)    ## a=10 b=20 a=10

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

## ── 17. Import ───────────────────────────────────────────────────────────────

## import plat : les symboles du fichier sont injectés dans le scope courant
import "utils_test"
assert(CONST == 42)

## import modulaire (fichier différent) : symboles regroupés dans une map
import "utils_test2" as u
assert(u.mul(3, 4) == 12)
assert(u.VERSION == 2)

## import circulaire : ignoré silencieusement (déjà importé)
import "utils_test"
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
end

var d = Dog("Rex")
assert(d.speak() == "Rex says woof")
assert(d.fetch() == "Rex fetches!")
assert(d.name == "Rex")

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

## metaméthodes arithmétiques
class Vec2
    func init(x, y)
        self.x = x
        self.y = y
    end
    func __add(other)
        return Vec2(self.x + other.x, self.y + other.y)
    end
    func __str()
        return "Vec2(" + self.x + "," + self.y + ")"
    end
end

var v1 = Vec2(1, 2)
var v2 = Vec2(3, 4)
var v3 = v1 + v2
assert(v3.x == 4)
assert(v3.y == 6)

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

## les erreurs ci-dessous sont des erreurs de COMPILATION :
##
##   const x          ## ERROR: must be initialized
##   const x = 1
##   x = 2               ## ERROR: cannot assign to const 'x'
##   x += 1              ## ERROR: cannot assign to const 'x'
##   const k = 1
##   func f()  k = 0  end  ## ERROR: cannot assign to const 'k'

## ── 20. Erreurs de redéclaration (erreurs de compilation) ───────────────────
##
##   var x = 1
##   var x = 2          ## ERROR: local variable 'x' already declared in this scope
##
##   global g = 1
##   global g = 2       ## ERROR: global variable 'g' already declared
##
##   func f(a)
##       var a = 1      ## ERROR: local variable 'a' already declared in this scope
##   end
##
## Une locale dans une AUTRE fonction ne provoque pas d'erreur :
##   var x = 1          ## OK : portée top-level
##   func f()
##       var x = 2      ## OK : portée distincte (registres de f)
##   end

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
## Module natif (non disponible en WASM/headless). Voir scripts/graphics_demo.ol.
##
##   graphics.canvas(800, 600, "Titre")   ## ouvre une fenêtre
##   graphics.run(func()
##       graphics.clear(graphics.BLACK)
##       graphics.line(x1, y1, x2, y2, 1, color)
##   end)
##
## Couleurs prédéfinies : BLACK, WHITE, RED, GREEN, BLUE, YELLOW, GRAY
## Couleurs personnalisées : (r << 24) | (g << 16) | (b << 8) | 255
## FPS : graphics.fps() → entier
## Texte : graphics.draw_text(text, x, y, size [, color])
