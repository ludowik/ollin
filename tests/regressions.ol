## Tests de non-régression — bugs corrigés lors des revues parser / compilateur.
## Chaque bloc verrouille un bug précis (aucun n'était attrapé par syntax.ol).
## Exécuter : ./build/ollin tests/regressions.ol  → doit finir sans erreur.

## ── Compilateur : multi-retour ──────────────────────────────────────────────
## #1 multi-retour depuis une CLOSURE (segfault avant : CALL_FUNC sans upvals)
var acc = 100
func split() return acc, acc * 2 end
var mr1, mr2 = split()
assert(mr1 == 100)
assert(mr2 == 200)

## #3 multi-retour depuis une MÉTHODE et un APPEL DYNAMIQUE (2e valeur = nil avant)
global obj = {}
func obj.two() return 10, 20 end
var me1, me2 = obj.two()
assert(me1 == 10)
assert(me2 == 20)

var dynf = func() return 7, 8 end
var dy1, dy2 = dynf()
assert(dy1 == 7)
assert(dy2 == 8)

## multi-retour nommé + global (non-régression)
func pair() return 1, 2 end
var pa1, pa2 = pair()
assert(pa1 == 1 and pa2 == 2)
global gl1, gl2 = pair()
assert(gl1 == 1 and gl2 == 2)

## ── Compilateur : clobber de registre sur appel 0-argument ──────────────────
## #4 objet[clé] / objet.champ où l'objet est un appel 0-arg (nil / crash avant)
func mkmap() return {x: 42} end
assert(mkmap().x == 42)
func mkarr() return [9, 8] end
assert(mkarr()[1] == 9)

## #5 switch sur un sujet appel 0-argument (mauvaise branche avant)
func subj() return 2 end
var branch = "none"
switch subj()
    case 1
        branch = "a"
    case 2
        branch = "b"
end
assert(branch == "b")

## ── Compilateur : super ─────────────────────────────────────────────────────
## #2 super sur 3 niveaux (récursion infinie avant : self.__class__.__parent__)
class SA
    func tag() return "A" end
end
class SB extends SA
    func tag() return super.tag() end
end
class SC extends SB
    func tag() return super.tag() end
end
assert(SC().tag() == "A")

## super 2 niveaux avec valeur (non-régression)
class NA
    func val() return 1 end
end
class NB extends NA
    func val() return super.val() + 10 end
end
assert(NB().val() == 11)

## ── VM : instancier une classe via un champ de map (cas alias.Classe()) ─────
class Widget
    func init(v) self.n = v end
end
global ns = {}
ns.W = Widget
var wi = ns.W(7)
assert(wi.n == 7)

## ── Parser : lvalues chaînées / indexées ────────────────────────────────────
## #7 affectations à cible chaînée (« unexpected token '=' » avant)
global cm = {b: {c: 0}}
cm.b.c = 9
assert(cm.b.c == 9)
cm.b.c += 5
assert(cm.b.c == 14)

global cf = {a: [0, 0]}
cf.a[1] = 7
assert(cf.a[1] == 7)

global nn = [[0]]
nn[1][1] = 9
assert(nn[1][1] == 9)

## self.champ.sous = ... dans une méthode
class Holder
    func init() self.p = {x: 0} end
    func setx(v) self.p.x = v end
end
var ho = Holder()
ho.setx(42)
assert(ho.p.x == 42)

## ── Parser : range ouvert à gauche au top-level ─────────────────────────────
## #8 ]a;b] au top-level (« ';' is not valid syntax » avant)
var openr = 0
for i in ]1; 4] do
    openr += i
end
assert(openr == 9)     ## 2 + 3 + 4

## ── VM : try/catch d'une erreur runtime venant d'une fonction APPELÉE ────────
## (avant : `base` non restauré dans le catch C++ → variable de catch erronée)
func vm_boom() assert(false, "kaboom") end
global caught = "none"
try
    vm_boom()
catch e
    caught = e
end
assert(caught == "kaboom")

## ── VM : destructuration multi-retour d'un appel à VALEUR UNIQUE → nil ───────
## (régression : builtin / constructeur / appel optionnel laissaient des
## registres périmés au lieu de nil)
var mrx = [4, 5, 6]
var la, lb = len(mrx)
assert(la == 3)
assert(lb == nil)
class MrPt
    func init(x, y) self.x = x self.y = y end
end
var pa, pb = MrPt(1, 2)
assert(pa.x == 1)
assert(pb == nil)
var mrf = nil
var oa, ob = mrf?()
assert(oa == nil and ob == nil)

## ── VM : <> respecte __eq (avant : == et <> vrais simultanément) ─────────────
class EqV
    func init(x) self.x = x end
    func __eq(o) return self.x == o.x end
end
assert(EqV(1) == EqV(1))
assert(not (EqV(1) <> EqV(1)))
assert(EqV(1) <> EqV(2))

## ── VM : comparaisons d'instances symétriques (__lt + __le) ──────────────────
## (avant : instance à gauche de > / droite de < levait une erreur)
class CmpN
    func init(v) self.v = v end
    func __lt(o) return self.v < o end
    func __le(o) return self.v <= o end
end
var cn = CmpN(5)
assert(cn < 9)
assert(9 > cn)
assert(cn > 3)      ## instance à GAUCHE de >
assert(3 < cn)      ## instance à DROITE de <
assert(cn >= 5)
assert(cn <= 5)

## ── VM : concaténation avec __str (pas de use-after-free) ────────────────────
class StrP
    func __str() return "SP" end
end
assert("x=" + StrP() == "x=SP")

## ── chunk : dédup des constantes STRICTE par type ───────────────────────────
## int 0 / float 0.0 / nil ont des bits nuls identiques mais des tags distincts →
## ne doivent PAS être fusionnés dans le pool (sinon nil deviendrait 0, etc.).
var ck_i = 0
var ck_f = 0.0
var ck_n = nil
assert(not (ck_i == ck_n))   ## int 0 n'est pas nil
assert(not (ck_f == ck_n))   ## float 0.0 n'est pas nil
assert(ck_i == ck_f)         ## 0 == 0.0 numériquement (2 constantes distinctes, mais égales)
assert(ck_n == nil)
## chaînes identiques → dédup (même contenu interné, une seule entrée de pool)
var ck_s1 = "dup-const"
var ck_s2 = "dup-const"
assert(ck_s1 == ck_s2)

## ── value : numValue ne fait plus de cast UB sur non-fini / hors plage ──────
## (math.* peut produire inf/nan ; un littéral flottant énorme dépasse int64)
assert(math.exp(1000) > 1000000000000000000)   ## inf → reste flottant, comparable
assert(math.sqrt(-1) <> math.sqrt(-1))          ## nan ≠ nan → reste un nan flottant
var big_f = 100000000000000000000.5
assert(big_f > 1000000000000000000)             ## ~1e20 → reste flottant (pas de cast UB)

## ── map : classes / ranges / builtins utilisables comme clés ────────────────
## (avant : ValueEqual retournait false par défaut pour T_CLASS/T_BUILTIN/T_RANGE
## → la clé insérée n'était jamais retrouvée)
class MK_A end
class MK_B end
global mk = {}
mk[MK_A] = 1
mk[MK_B] = 2
assert(mk[MK_A] == 1)
assert(mk[MK_B] == 2)          ## deux classes distinctes = deux clés distinctes
var mk_r = [1; 5]
mk[mk_r] = 7
assert(mk[mk_r] == 7)          ## range comme clé
mk[print] = 9
assert(mk[print] == 9)         ## builtin comme clé
## int et float-entier restent la MÊME clé (1 == 1.0) — cohérence hash/equal
global mk2 = {}
mk2[1] = 10
assert(mk2[1.0] == 10)
## clé float ENTIÈRE hors plage int64 (avant : ValueHash faisait un cast int64 UB —
## trap sur WASM). doit fonctionner comme n'importe quelle clé.
var mk_huge = math.pow(2.0, 100)     ## 2^100, float entier >> 2^63
mk2[mk_huge] = 42
assert(mk2[mk_huge] == 42)
mk2[-mk_huge] = 43
assert(mk2[-mk_huge] == 43)

## ── range : bornes non finies rejetées + itération (chemin itérateur dévirtualisé) ──
## (avant : MAKE_RANGE et FOR_PREP acceptaient inf/NaN → itération infinie / gel)
global rng_c1 = "none"
try
    for i = 0.0, math.exp(1000) do break end   ## for numérique, borne +inf
catch e
    rng_c1 = "x"
end
assert(rng_c1 == "x")                          ## doit lever, pas boucler
global rng_c2 = "none"
try
    var rng_bad = ]0; math.exp(1000)]          ## range ouvert (MAKE_RANGE), borne +inf
catch e
    rng_c2 = "x"
end
assert(rng_c2 == "x")
global rng_c3 = "none"
try
    var rng_nan = [0; math.sqrt(-1)]           ## borne NaN
catch e
    rng_c3 = "x"
end
assert(rng_c3 == "x")
var rng_s = 0
for i in ]1; 5] do rng_s += i end              ## open-left → itérateur range (dévirtualisé)
assert(rng_s == 14)                            ## 2+3+4+5
var rng_r = [1; 4]
var rng_t = 0
for i in rng_r do rng_t += i end               ## range value → itérateur range
assert(rng_t == 10)                            ## 1+2+3+4

## ── builtin static : cohérence classe/instance (comme un `static func` Ollin) ──
## Un builtin déclaré static ne reçoit pas self → son 1er param est en R[0], que
## l'appel soit sur la classe ou sur une instance (avant : self injecté sur instance
## → le param se retrouvait décalé et l'argument était mal interprété).
var col_a = Color.gray(0.5)              ## fabrique statique paramétrée, sur la classe
assert(col_a.r == 0.5 and col_a.b == 0.5)
var col_c = Color(1, 0, 0)
var col_b = col_c.gray(0.25)            ## MÊME méthode, sur une instance → param en R[0]
assert(col_b.r == 0.25 and col_b.g == 0.25)
assert(Color.random().a == 1 and col_c.random().a == 1)  ## random statique, deux modes

## ── core : print de plusieurs instances à __str (avant : use-after-free) ──────
## valueToString(__str) exécute du bytecode et peut réallouer regs ; print lisait
## args[i] directement dans regs → pointeur pendant pour les args suivants. Corrigé
## en copiant les args (comme printf). On vérifie juste que ça ne crashe pas.
class PrUAF
    func init(n) self.n = n end
    func __str() return "P" + self.n end
end
func pr_deep(d)
    if d > 0 then
        return pr_deep(d - 1)
    end
    return PrUAF(9)
end
print(PrUAF(1), 42, PrUAF(2), PrUAF(3))
print(pr_deep(30), PrUAF(4), pr_deep(20))

## ── math : cohérence int (clamp/pow/logn repliés comme MATH1/min-max) + map/0 ──
assert(typeof(math.clamp(5, 0, 10)) == "int")   ## avant : float
assert(math.clamp(5, 0, 10) == 5)
assert(typeof(math.pow(2, 3)) == "int" and math.pow(2, 3) == 8)
assert(typeof(math.pow(2, 0.5)) == "float")     ## non entier reste float
assert(typeof(math.logn(8, 2)) == "int" and math.logn(8, 2) == 3)
assert(math.map(5, 2, 2, 7, 99) == 7)           ## plage d'entrée nulle → out_lo (pas d'inf/nan)
assert(not math.isInf(math.map(5, 2, 2, 0, 10)))
assert(math.map(5, 0, 10, 0, 100) == 50)

## ── string/math : cast double→int gardé (avant : UB / trap WASM sur index géant) ──
assert(string.char("abc", 1e300) == "")         ## index hors plage → "" (pas de trap)
assert(string.char("abc", math.sqrt(-1)) == "") ## NaN
assert(string.substr("hello", 1e300) == "")
assert(string.substr("hello", 2, 1e300) == "ello")  ## len géant → clampé
assert(string.char("abc", 2) == "b")            ## cas normal
global str_c = "none"
try
    var r = math.randInt(1e300)                ## arg hors plage int64 → erreur claire
catch e
    str_c = "x"
end
assert(str_c == "x")

## ── string : indexation par CARACTÈRE (codepoint UTF-8), pas par octet ────────
assert(len("café") == 4)                     ## 4 caractères (é = 2 octets)
assert(len("héllo") == 5)
assert(len("a€b") == 3)                       ## € = 3 octets, 1 caractère
assert(string.char("café", 4) == "é")        ## avant : fragment d'octet
assert(string.char("a€b", 2) == "€")
assert(string.substr("café", 1, 3) == "caf")
assert(string.substr("café", 4, 1) == "é")
assert(string.substr("héllo", 2, 2) == "él")
assert(len("hello") == 5)                     ## ASCII inchangé
assert(string.char("café", 9) == "")         ## hors limites → ""
## upper/lower : ASCII + Latin-1 accentué ; trim par codepoint
assert(string.upper("café") == "CAFÉ")
assert(string.lower("ÉÀÙÇ") == "éàùç")
assert(string.upper("straße") == "STRASSE")  ## ß → SS
assert(string.trim("··café··", "·") == "café")  ## trim par codepoint (· = 2 octets)
assert(string.rtrim("«café»", "»") == "«café")
## string.len : longueur par codepoint, string uniquement (pas polymorphe comme len global)
assert(string.len("café") == 4)               ## é = 2 octets, 1 caractère
assert(string.len("a€b") == 3)                ## € = 3 octets, 1 caractère
assert(string.len("") == 0)
assert(string.len("hello") == len("hello"))   ## cohérent avec le len global sur string
global str_len_err = "none"
try
    string.len([1, 2, 3])                     ## non-string → erreur (contrairement à len global)
catch e
    str_len_err = "caught"
end
assert(str_len_err == "caught")

## if imbriqué en 1re position d'une branche else (pas de sucre "else if" → elseif)
var ei = "?"
if false then
    ei = "then"
else
    if true then
        ei = "else>if"
    end
end
assert(ei == "else>if")
## elseif reste distinct et fonctionnel
var ec = 0
if false then
    ec = 1
elseif true then
    ec = 2
else
    ec = 3
end
assert(ec == 2)

## mem() : mémoire tas utilisée (octets, entier) — croît avec les allocations
assert(typeof(mem()) == "int")
assert(mem() > 0)
var mem_before = mem()
var big = []
for i = 1, 20000 do
    big[i] = i
end
assert(mem() >= mem_before)     ## l'allocation d'un grand array n'a pas fait baisser la mémoire

## ── Compilateur : portée lexicale des `var` (visible à partir de sa déclaration) ──
## Bug : une `var` déclarée plus loin masquait une référence antérieure → lecture du
## registre non initialisé (nil au top-level, valeur résiduelle en fonction). Désormais
## avant sa ligne le nom résout au global ; la locale ne masque qu'à partir du `var`.
global lex_g = 2
assert(lex_g == 2)          ## référence AVANT le `var lex_g` ci-dessous → le global
var lex_g = 1               ## à partir d'ici : locale
assert(lex_g == 1)

## `var x = x` : l'initialisateur lit le x EXTÉRIEUR, pas la locale en cours
global lex_h = 7
func lex_init()
    var lex_h = lex_h + 1   ## RHS = global (7) → locale = 8
    return lex_h
end
assert(lex_init() == 8)
assert(lex_h == 7)          ## global inchangé

## bloc `do` : même règle, cloisonné
global lex_b = 3
do
    assert(lex_b == 3)      ## avant le var du bloc → global
    var lex_b = 9
    assert(lex_b == 9)
end
assert(lex_b == 3)          ## hors du bloc → global de nouveau

## ── Compilateur : expansion de `...` et spread d'appel terminal ─────────────
## `...` et un appel en DERNIÈRE position s'étendent à TOUTES leurs valeurs (Lua).
## Auparavant `...` ne donnait qu'une valeur (ou du garbage si vide) hors `return`.
func va_sum(...)
    var s = 0
    for v in [...] do s += v end   ## [...] = toutes les varargs
    return s
end
assert(va_sum() == 0)
assert(va_sum(1, 2, 3, 4) == 10)

## forwarding : f(head, ...) transmet toutes les varargs (argc dynamique)
func va_fwd(head, ...) return head + va_sum(...) end
assert(va_fwd(100, 1, 2, 3) == 106)

## multi-usage des varargs dans le même corps (pas de corruption après spread)
func va_twice(...)
    var a = va_sum(...)
    var b = va_sum(...)
    return a + b
end
assert(va_twice(1, 2, 3) == 12)

## ... en valeur simple : 1ʳᵉ vararg, ou nil si aucune (plus de garbage)
func va_first(...) return ... end
var vf = va_first(9, 8)
assert(vf == 9)

## multi-affectation depuis ... : var a, b = ...
func va_take2(...)
    var a, b = ...
    return a, b
end
var vt1, vt2 = va_take2(11, 22, 33)
assert(vt1 == 11 and vt2 == 22)
var vu1, vu2 = va_take2(5)
assert(vu1 == 5 and vu2 == nil)

## spread d'appel terminal : f(a, g()), return g(), [x, g()]
func va_pair() return 1, 2 end
func va_add3(a, b, c) return a + b + c end
assert(va_add3(10, va_pair()) == 13)        ## g() étendu en dernier argument
func va_ret() return va_pair() end
var vr1, vr2 = va_ret()
assert(vr1 == 1 and vr2 == 2)               ## return d'un appel terminal étendu
var va_a = [0, va_pair()]
assert(len(va_a) == 3 and va_a[2] == 1 and va_a[3] == 2)  ## [x, g()] étendu

## un appel en position NON finale est ajusté à 1 valeur (Lua)
func va_one(x) return x end
assert(va_one(va_pair()) == 1)

## ── Compilateur : masquage lexical par bloc ─────────────────────────────────
## Un `var` dans un bloc imbriqué masque la locale externe (registre distinct) ;
## l'externe est intacte après le bloc. Régressé un temps par bindScanLocals qui
## réutilisait le registre externe quand le nom était déjà lié (portée héritée).
var shadow_x = 1
do
    var shadow_x = 99
    assert(shadow_x == 99)
end
assert(shadow_x == 1)
## l'initialisateur lit la portée d'avant la déclaration (var z = z externe)
func shadow_outer()
    var z = 3
    do
        var z = z + 100   ## RHS = z externe (3)
        assert(z == 103)
    end
    return z              ## externe intacte
end
assert(shadow_outer() == 3)

## ── Formatage {expr:spec} (interpolation) et {N:spec} (printf), moteur partagé ──
## Le ':' de spec est celui de PREMIER niveau : un map-littéral imbriqué le préserve.
var fmt_v = 3.14159
assert("{fmt_v:.2f}" == "3.14")
assert("{fmt_v:8.3f}" == "   3.142")           ## largeur + précision
assert("{(255):x}" == "ff")                     ## hexa (expression parenthésée)
assert("{(255):#06x}" == "0x00ff")             ## flag # + zéro-pad + largeur
assert("{(-7):+d}" == "-7")                     ## signe forcé
assert("{(42):d}" == "42")
assert("{(3.9):d}" == "3")                       ## coercition float→int (troncature)
assert("{"hi":5s}" == "   hi")                 ## largeur 5, aligné à droite (défaut C)
assert("{"hi":-5s}" == "hi   ")                ## '-' = aligné à gauche (syntaxe printf C, pas '>')
## le ':' d'un map imbriqué N'EST PAS un séparateur de spec
var fmt_m = {"a": 1}
assert("{fmt_m["a"]}" == "1")
assert("{ {"k": 7}.k }" == "7")
## {N} / {} sont des placeholders positionnels → LITTÉRAUX hors printf
assert("{1}-{2}" == "{1}-{2}")
assert("{}" == "{}")                             ## plus d'erreur « interpolation vide »
## spec invalide → erreur runtime claire
var fmt_err = false
try
    var bad = "{fmt_v:.2z}"
    print(bad)
catch e
    fmt_err = true
end
assert(fmt_err)

## map.len() : la pseudo-méthode `len` intégrée reçoit bien la map en self
## (les maps n'injectent pas self sinon — module vs pseudo-méthode)
var mlen = {a: 1, b: 2, c: 3}
assert(mlen.len() == 3)
mlen["d"] = 4
assert(mlen.len() == 4)
assert({}.len() == 0)
var mlen_def = {len: 42}          ## une entrée "len" définie gagne sur le builtin
assert(mlen_def.len == 42)

## inline cache GET_INDEX : invalidation à la mutation de la map (version)
var ic = {x: 1, y: 2}
var ic_a = ic.x            ## remplit le cache (ic, "x") = 1
ic["x"] = 99               ## mutation → version bump → cache invalidé
assert(ic_a == 1)
assert(ic.x == 99)         ## doit relire, pas servir 1
ic["x"] = "str"            ## changement de type via le même site
assert(ic.x == "str")
var ic_s = 0               ## site en boucle avec mutation à chaque tour
for i = 1, 5 do
    ic["x"] = i
    ic_s += ic.x
end
assert(ic_s == 15)

print("regressions ok")
