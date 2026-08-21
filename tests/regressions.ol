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

## #5 appel 0-arg comme opérande GAUCHE : son résultat ne doit pas être écrasé par
## l'évaluation de l'opérande droit
func mk5() return 5 end
func mk3() return 3 end
assert(mk5() + 2 == 7)
assert(mk5() + mk3() == 8)

## #6 switch sur un sujet appel 0-argument (mauvaise branche avant)
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

## inline cache GET_INDEX : le cache ne porte que sur la data PROPRE de l'objet.
## Une résolution via la chaîne (__class__/__parent__) n'est PAS cachée → une
## mutation de la classe reste visible depuis une instance déjà créée.
class ICA
    func init(v)
        self.v = v
    end
    func kind()
        return "ICA"
    end
end
class ICB extends ICA
    func kind()
        return "ICB"
    end
end
var ica = ICA(1)
assert(ica.v == 1)         ## champ propre → cacheable
ica.v = 2
assert(ica.v == 2)         ## mutation de l'instance → version bump → pas de périmé
ICA["tag"] = "c1"
assert(ica.tag == "c1")    ## via la chaîne (non cachée)
ICA["tag"] = "c2"
assert(ica.tag == "c2")    ## re-mutation de la classe bien vue
ica["tag"] = "own"
assert(ica.tag == "own")   ## la data propre masque la classe
var icb = ICB(5)
assert(icb.kind() == "ICB")
assert(icb.get_v_ok == nil)
assert(ICB.tag == "c2")    ## héritée via __parent__

## pseudo-méthodes de tableau servies par array_module (plus de chaîne de strcmp
## dans GET_INDEX) : un champ inconnu doit rester une ERREUR, pas nil.
var arr_err = false
try
    var bad_field = [1, 2].zzz
    print(bad_field)
catch e
    arr_err = true
end
assert(arr_err)
## tri : comparateur explicite, et ordre par rang de type sans comparateur
var srt = [1, 2, 3].sort(func(x, y) return x > y end)
assert(srt[1] == 3)
assert(srt[3] == 1)
var srt_mix = [3, "a", nil, 1].sort()
assert(srt_mix[1] == nil)      ## nil < nombres < chaînes
assert(srt_mix[2] == 1)
assert(srt_mix[4] == "a")
## insert(v) == push, insert(i, v) positionnel (1-based)
var ins = [1, 2]
ins.insert(9)
assert(ins[3] == 9)
ins.insert(1, 7)
assert(ins[1] == 7)

## inline cache : la valeur cachée est une référence NON possédante vers
## l'emplacement dans la map. Le registre destination peut aliaser celui de
## l'objet (`m = m.inner`) : l'écriture détruirait la map d'où provient la valeur
## → la copie doit être faite AVANT d'écrire le registre.
var ali = {inner: {v: 42}}
ali = ali.inner
assert(ali.v == 42)
var deep = {x: {x: {x: 9}}}
var pd = deep
for i = 1, 2 do
    pd = pd.x
end
assert(pd.x == 9)

## `nil` vaut ABSENT dans une map : une clé propre valant nil ne masque PAS ce que
## la chaîne de prototypes (ou le repli `len`) fournirait. Régression possible en
## passant d'un lookup par valeur à un lookup par présence de clé.
class NilSh
    func init()
        self.a = 1
    end
    func m()
        return "classe"
    end
end
var nsh = NilSh()
nsh["m"] = nil
assert(nsh.m() == "classe")     ## la méthode de classe reste atteignable
var nlen = {}
nlen["len"] = nil
assert(nlen.len() == 1)         ## repli `len` intégré ; la map a 1 clé

## ── enum ─────────────────────────────────────────────────────────────────────
## Numérotation : 1 par défaut, +1 ensuite ; un littéral entier redéfinit la suite ;
## une valeur non littérale (ici une chaîne) laisse le compteur où il est.
enum RgEtat REPOS = 0, MARCHE, SAUT = 10, CHUTE end
assert(RgEtat.REPOS == 0 and RgEtat.MARCHE == 1)
assert(RgEtat.SAUT == 10 and RgEtat.CHUTE == 11)
enum RgMix A, B = "texte", C end
assert(RgMix.A == 1 and RgMix.B == "texte" and RgMix.C == 2)
enum RgNeg X = -3, Y end
assert(RgNeg.X == -3 and RgNeg.Y == -2)
enum RgAlias UN = 1, PREMIER = 1 end       ## valeur répétée = alias, permis
assert(RgAlias.UN == RgAlias.PREMIER)

## Un enum est une map ordinaire en LECTURE : len, itération, valeurs de tout type.
enum RgCol ROUGE, VERT, BLEU end
assert(#RgCol == 3)
var rg_sum = 0
for k, v in RgCol do
    rg_sum = rg_sum + v
end
assert(rg_sum == 6)
func rg_carre(x) return x * x end
enum RgObj L = [1, 2, 3], F = rg_carre end
assert(RgObj.L[2] == 2 and RgObj.F(5) == 25)

## Gel SUPERFICIEL : l'enum refuse l'écriture, pas l'objet qu'il contient.
RgObj.L[1] = 99
assert(RgObj.L[1] == 99)

## Verrou à l'exécution : alias et clé calculée passent par le même SET_INDEX.
var rg_alias = RgCol
var rg_caught = 0
try
    rg_alias.ROUGE = 9
catch e
    rg_caught = rg_caught + 1
end
try
    var rg_k = "VERT"
    rg_alias[rg_k] = 9
catch e
    rg_caught = rg_caught + 1
end
assert(rg_caught == 2 and RgCol.ROUGE == 1 and RgCol.VERT == 2)

## enum dans une map existante (chemin `a.b`).
global rgCfg = {}
enum rgCfg.mode PLEIN, FENETRE end
assert(rgCfg.mode.PLEIN == 1 and rgCfg.mode.FENETRE == 2)

## Recyclage du pool : le marquage enum ne doit pas contaminer une map réutilisée.
## Les maps ci-dessous sont libérées puis leur mémoire est réattribuée.
for i = 1, 200 do
    var rg_tmp = {a: i}
    rg_tmp.a = i + 1
    assert(rg_tmp.a == i + 1)
end
var rg_libre = {}
rg_libre.x = 1
assert(rg_libre.x == 1)


## Export d'un module : toutes les sortes de déclarations doivent se retrouver dans
## la map créée par `import ... as`. Un enum y manquait (collect_top_level_names ne
## connaissait pas EnumDeclStmt), donc m.MonEnum valait nil.
import "exports_test" as expMod
assert(expMod.expVar == 1)
assert(expMod.expGlobal == 2)
assert(expMod.expFunc() == 3)
assert(ExpClass().v == 4)          ## la classe est exportée (instanciable via le nom)
assert(expMod.ExpClass <> nil)
assert(expMod.ExpEnum.A == 1 and expMod.ExpEnum.B == 2)
assert(expMod.dansUneMap == nil)   ## `enum a.b` n'exporte pas de nom propre


## Pré-scan des globaux : un `global` déclaré au FOND de chaque sorte de construction
## doit être vu avant la compilation. Ces fonctions le lisent alors qu'elles sont
## déclarées AVANT la déclaration du global : si le parcours ne descend pas dans une
## construction, la compilation échoue sur « undeclared variable ».
## (Verrouille Stmt::for_each_body : une instruction à corps oubliée casse ici.)
func psLire() return psWhile + psIf + psElseIf + psElse + psFor + psFunc + psDo end
func psLire2() return psSwitch + psSwitchElse + psTry + psCatch + psTryElse + psMethode end

while true do
    global psWhile = 1
    break
end
if true then
    global psIf = 2
elseif false then
    global psElseIf = 3
else
    global psElse = 4
end
if false then
    psElseIf = 3
end
psElseIf = 3
psElse = 4
for i = 1, 1 do
    global psFor = 5
end
func psPorteuse()
    global psFunc = 6
end
psPorteuse()
do
    global psDo = 7
end
switch 1
    case 1 do
        global psSwitch = 8
    end
    else
        global psSwitchElse = 9
end
psSwitchElse = 9
try
    global psTry = 10
    throw "x"
catch e
    global psCatch = 11
end
try
    var psRien = 0
catch e
else
    global psTryElse = 12   ## bloc `else` du try : exécuté si aucune exception
end
class PsClasse
    func m()
        global psMethode = 13
        return psMethode
    end
end
PsClasse().m()

assert(psLire() == 1 + 2 + 3 + 4 + 5 + 6 + 7)
assert(psLire2() == 8 + 9 + 10 + 11 + 12 + 13)


## Closure capturant la variable de boucle depuis un bloc IMBRIQUÉ. body_has_func
## décide si la boucle ferme ses upvalues et garde ses registres réservés ; il n'avait
## pas de cas pour `do ... end` (no-op hérité) et répondait « aucune fonction ici » →
## registres recyclés, et la closure lisait un registre réutilisé : dfDo[1]() renvoyait
## {function} au lieu d'un nombre. Chaque itération a sa propre variable.
var dfDo = []
for i = 1, 3 do
    do
        dfDo[#dfDo + 1] = func() return i end
    end
end
assert(dfDo[1]() == 1 and dfDo[2]() == 2 and dfDo[3]() == 3)

var dfIf = []
for i = 1, 3 do
    if true then
        dfIf[#dfIf + 1] = func() return i end
    end
end
assert(dfIf[1]() == 1 and dfIf[3]() == 3)

var dfSw = []
for i = 1, 3 do
    switch 1
        case 1 do
            dfSw[#dfSw + 1] = func() return i end
        end
    end
end
assert(dfSw[1]() == 1 and dfSw[3]() == 3)

var dfTry = []
for i = 1, 3 do
    try
        dfTry[#dfTry + 1] = func() return i end
    catch e
    end
end
assert(dfTry[1]() == 1 and dfTry[3]() == 3)


## Closure capturant une LOCALE DU CORPS de boucle, appelée APRÈS la boucle.
## compile_block réserve les registres des locales du corps quand celui-ci contient une
## fonction ; les deux boucles écrasaient ensuite reg_top_ avec la seule réservation des
## variables de boucle, plus basse → le registre de la locale redevenait un temporaire,
## et l'appel suivant écrasait la valeur sous une upvalue encore ouverte (on lisait
## {function} au lieu de la valeur).
var clNum = []
for i = 1, 3 do
    var copie = i * 10
    clNum[#clNum + 1] = func() return copie end
end
assert(clNum[1]() == 10 and clNum[2]() == 20 and clNum[3]() == 30)

var clIter = []
for v in ["a", "b", "c"] do
    var copie = v
    clIter[#clIter + 1] = func() return copie end
end
assert(clIter[1]() == "a" and clIter[2]() == "b" and clIter[3]() == "c")

var clPaire = []
for k, v in {x: 1} do
    var copie = k + "=" + v
    clPaire[#clPaire + 1] = func() return copie end
end
assert(clPaire[1]() == "x=1")


## Fermeture des upvalues en fin d'itération (CLOSE_UPVALS) : les chemins de sortie et
## de rebouclage doivent TOUS y passer, et deux closures d'un même tour doivent
## continuer à PARTAGER leur variable (une seule upvalue par registre et par tour).
var upBreak = []
for i = 1, 5 do
    upBreak[#upBreak + 1] = func() return i end
    if i == 3 then break end
end
assert(#upBreak == 3 and upBreak[1]() == 1 and upBreak[3]() == 3)

var upCont = []
for i = 1, 4 do
    if i % 2 == 0 then continue end
    upCont[#upCont + 1] = func() return i end
end
assert(#upCont == 2 and upCont[1]() == 1 and upCont[2]() == 3)

var upPart = []
for i = 1, 2 do
    var n = i * 10
    upPart[#upPart + 1] = [func() return n end, func() n = n + 1 end]
end
var upP1 = upPart[1]
upP1[2]()                       ## écrit dans la variable du PREMIER tour
var upP2 = upPart[2]
assert(upP1[1]() == 11 and upP2[1]() == 20)

var upNest = []
for i = 1, 2 do
    for j = 1, 2 do
        upNest[#upNest + 1] = func() return i * 10 + j end
    end
end
assert(upNest[1]() == 11 and upNest[2]() == 12 and upNest[3]() == 21 and upNest[4]() == 22)

func upReturn()
    for i = 1, 3 do
        var f = func() return i end
        if i == 2 then
            return f
        end
    end
end
assert(upReturn()() == 2)


## ── ref (passage par référence) ───────────────────────────────────────────────
## `ref x` est désucré par le parser en {__ref, get, set} : deux closures qui lisent
## et écrivent la cible. Les upvalues font le travail, y compris pour une locale.
global rfGlobal = 5
var rfLocale = 1
global rfObj = {champ: "a", sous: {x: 1}}

func rfLire(r) return r.get() end
func rfEcrire(r, v) r.set(v) end

assert((ref rfGlobal).__ref)              ## marque de validation pour les modules natifs
assert(rfLire(ref rfGlobal) == 5)
rfEcrire(ref rfGlobal, 42)
assert(rfGlobal == 42)
rfEcrire(ref rfLocale, 7)                 ## écriture d'une LOCALE depuis une autre fonction
assert(rfLocale == 7)
rfEcrire(ref rfObj.champ, "b")
assert(rfObj.champ == "b")
rfEcrire(ref rfObj.sous.x, 99)            ## chemin de deux niveaux
assert(rfObj.sous.x == 99)

## Le paramètre du setter généré ne doit JAMAIS masquer la cible : `ref v` a produit
## `func(v) v = v end` dans une version naïve, donc une écriture sans effet.
var v = 1
rfEcrire(ref v, 9)
assert(v == 9)

## La référence est une valeur ordinaire : stockable, transmissible.
var rfStock = ref rfGlobal
rfStock.set(3)
assert(rfGlobal == 3)

## Référence prise sur une locale de BLOC : lisible après la sortie du bloc (l'upvalue
## est fermée sur une copie), l'écriture ne remonte plus nulle part — comportement figé
## ici pour qu'un changement du mécanisme d'upvalue se voie.
var rfEchappe = nil
do
    var rfInterne = "dedans"
    rfEchappe = ref rfInterne
end
assert(rfEchappe.get() == "dedans")


## ── Module tween ────────────────────────────────────────────────────────────────
## Avancement par pas EXACTS (0,25 × 4) : un pas de 0,1 accumulé dix fois ne fait pas
## tout à fait 1 seconde en binaire, et le tween ne serait pas terminé.
tween.cancelAll()
var twObj = {x: 0, n: 0, teinte: Color(0, 0, 0)}
var twT = tween.to(twObj, {x: 8}, 1.0, "linear")
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 4 and twT.progress() == 0.5)
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 8 and twT.isDone() and tween.count() == 0)

## Un pas plus long que la durée restante s'arrête à la cible, sans dépassement.
tween.to(twObj, {x: 5}, 0.5, "linear")
tween.update(10.0)
assert(twObj.x == 5)

## Départ ET cible entiers → la valeur reste entière tout du long (pas de dérive float).
tween.to(twObj, {n: 10}, 1.0, "linear")
tween.update(0.5)
assert(twObj.n == 5 and typeof(twObj.n) == "int")

## Courbe à dépassement : la valeur finale doit être la cible EXACTE, pas 0,99.
var twFini = false
tween.to(twObj, {x: 20}, 0.5, "easeOutBack", func() twFini = true end)
tween.update(0.5)
assert(twObj.x == 20 and twFini)

## Interpolation structurelle : une instance de classe s'anime champ par champ.
tween.to(twObj, {teinte: Color(1, 0.5, 0)}, 1.0, "linear")
tween.update(1.0)
assert(twObj.teinte.r == 1 and twObj.teinte.g == 0.5 and twObj.teinte.b == 0)

## Variable simple par référence, et courbe donnée sous forme de FONCTION.
var twVal = 0
tween.value(ref twVal, 100, 1.0, func(p) return p * p end)
tween.update(0.5)
assert(twVal == 25)
tween.update(0.5)
assert(twVal == 100)

## Deux tweens sur le MÊME champ : le second annule le premier (sinon ils se battraient
## et le résultat dépendrait de l'ordre d'itération).
twObj.x = 0
tween.to(twObj, {x: 50}, 1.0, "linear")
tween.to(twObj, {x: -50}, 1.0, "linear")
assert(tween.count() == 1)
tween.update(1.0)
assert(twObj.x == -50)

## Délai : rien ne bouge avant l'échéance, et la valeur de départ est celle du DÉMARRAGE.
twObj.x = 0
tween.to(twObj, {x: 10}, 1.0, "linear").delay(0.5)
tween.update(0.4)
assert(twObj.x == 0)
twObj.x = 100          ## écrit pendant le délai → c'est de là que part l'animation
tween.update(0.6)      ## 0,1 s de délai restant, puis 0,5 s d'animation
assert(twObj.x == 55)

## Pause / reprise.
twObj.x = 0
var twP = tween.to(twObj, {x: 10}, 1.0, "linear")
tween.update(0.5)
twP.pause()
tween.update(0.5)
assert(twObj.x == 5)
twP.resume()
tween.update(0.5)
assert(twObj.x == 10)

## Un rappel de fin qui DÉCLARE un tween : il fait push_back sur la table pendant la
## passe d'avancement, donc toute référence conservée à travers l'appel serait pendante.
var twChain = 0
tween.to(twObj, {x: 0}, 0.5, "linear", func()
    twChain = 1
    tween.to(twObj, {x: 7}, 0.5, "linear", func() twChain = 2 end)
end)
tween.update(0.5)
assert(twChain == 1)
tween.update(0.5)
assert(twChain == 2 and twObj.x == 7)

## Un rappel de fin qui ANNULE tout : la passe ne doit pas continuer sur des slots morts.
tween.to(twObj, {x: 1}, 0.5, "linear", func() tween.cancelAll() end)
tween.to(twObj, {n: 1}, 0.5, "linear")
tween.update(0.5)
assert(tween.count() == 0)

## Une COURBE fournie par le script peut déclarer d'autres tweens : la table se réalloue
## en pleine passe d'avancement, donc rien ne doit conserver de référence sur un élément.
tween.cancelAll()
var twR = {x: 0, y: 0}
var twN = 0
tween.to(twR, {x: 100}, 1.0, func(p)
    twN += 1
    if twN == 1 then
        tween.to(twR, {y: 50}, 1.0, "linear")
    end
    return p
end)
tween.update(0.5)
tween.update(0.5)
## y = 25 : le tween né dans la 1re passe n'y est PAS avancé (il consommerait un pas de
## temps antérieur à sa naissance), il ne reçoit donc que la seconde — la valeur ne dépend
## plus du slot qui lui a été attribué.
assert(twR.x == 100 and twR.y == 25)

## ── ui.list ─────────────────────────────────────────────────────────────────────
## Sans zone graphique, la déclaration valide ses arguments et initialise la sélection :
## c'est cette part-là qui se teste ici (le rendu et le clic demandent un affichage).
## Un tableau renvoie une VALEUR, une map ou un enum une CLÉ — comme `for … in`.
enum LiDiff
    facile,
    normal,
    difficile
end
var liCouleurs = ["rouge", "vert", "bleu"]
var liReglages = {volume: 0.8, brillance: 0.5, alpha: 1}
var liC = nil
var liD = nil
var liR = nil
ui.list("Couleur", liCouleurs, ref liC)
ui.list("Difficulté", LiDiff, ref liD)
ui.list("Réglage", liReglages, ref liR)
assert(liC == "rouge")           ## 1er élément du tableau, sa VALEUR
assert(liD == "facile")          ## enum trié par valeur → ordre de déclaration
assert(liR == "alpha")           ## map triée par libellé → premier dans l'ordre alphabétique

## Une sélection déjà posée est respectée (l'initialisation ne vaut que pour nil).
var liGarde = "bleu"
ui.list("Couleur", liCouleurs, ref liGarde)
assert(liGarde == "bleu")

## Handle d'un tween terminé : interrogeable sans erreur (garder le handle est normal).
assert(twT.isDone() and twT.progress() == 1)
twT.cancel()

## Réaffectation multiple (sans `var`) d'un appel multi-retour : la même valeur devait
## atteindre la même cible qu'à la déclaration. Le compilateur ne comptait qu'UNE valeur
## et les cibles suivantes lisaient des registres voisins → valeurs décalées (1, 1, 2).
func maTrois()
    return 1, 2, 3
end
func maUne()
    return 7
end
global maG1 = 0
global maG2 = 0
var maA, maB, maC = maTrois()
maA, maB, maC = maTrois()
assert(maA == 1 and maB == 2 and maC == 3)
maG1, maG2 = maTrois()
assert(maG1 == 1 and maG2 == 2)
## Moins de valeurs que de cibles : les cibles au-delà passent à nil, pas à un reste de registre.
var maX = 5
var maY = 5
maX, maY = maUne()
assert(maX == 7 and maY == nil)
## Cibles qui ne sont pas de simples variables.
var maM = {}
maM.u, maM.v = maTrois()
assert(maM.u == 1 and maM.v == 2)
var maT = [0, 0, 0]
maT[1], maT[3] = maTrois()
assert(maT[1] == 1 and maT[2] == 0 and maT[3] == 2)
## Échange : deux valeurs pour deux cibles reste un cas parallèle, pas un multi-retour.
var maP = 1
var maQ = 2
maP, maQ = maQ, maP
assert(maP == 2 and maQ == 1)
## Méthode et varargs empruntent le même chemin que la fonction nommée.
class MaPaire
    func deux()
        return 8, 9
    end
end
var maObj = MaPaire()
var maD1 = 0
var maD2 = 0
maD1, maD2 = maObj.deux()
assert(maD1 == 8 and maD2 == 9)
func maVarargs(...)
    var maV1, maV2 = ...
    maV1, maV2 = ...
    assert(maV1 == "a" and maV2 == "b")
end
maVarargs("a", "b")

## ── Compilateur : sémantique de la variable de boucle ───────────────────────
## Trois règles qu'une optimisation a déjà cassées : l'aliasage du compteur, la portée de
## la variable, et la fermeture des upvalues en fin de tour.

## Modifier la variable de boucle dans le corps n'affecte pas l'itération : le compteur
## est isolé de la variable visible (chemin sans alias).
var boS = 0
var boN = 0
for i = 1, 3 do
    boS += i
    i = i + 100
    boN += 1
end
assert(boS == 6 and boN == 3)

## La variable de boucle est locale à la boucle : une variable externe de même nom est
## masquée pendant, puis restaurée.
var boExt = 99
for boExt = 1, 3 do end
assert(boExt == 99)

## Une variable PAR ITÉRATION : les upvalues sont fermées en fin de tour, donc chaque
## closure garde la valeur de son propre tour (modèle Lua 5.4 / `let`).
var boCl = []
var boI = 0
for v in [10, 20, 30] do
    boI += 1
    boCl[boI] = func() return v end
end
assert(boCl[1]() == 10 and boCl[2]() == 20 and boCl[3]() == 30)

## ── tween : plan de lecture (repeat) ────────────────────────────────────────
## `repeat([occurrences] [, allerRetour])` : sans compte, la répétition est sans fin ; le
## second paramètre ajoute le retour de l'ENSEMBLE. Les positions sont relevées tous les
## demi-temps, l'animation durant 1 s : on lit donc le milieu puis l'extrémité de chaque
## parcours. En natif headless c'est `tween.update` qui avance (le moteur ne tourne pas).
func plParcours(mods, tours)
    var o = {x: 0}
    var t = tween.to(o, {x: 10}, 1.0, "linear")
    mods(t)
    var vues = []
    for i = 1, tours do
        tween.update(0.5)
        vues[#vues + 1] = math.round(o.x)
    end
    return vues
end

## repeat(2) : deux allers. À la fin du premier, la position revient au départ.
var plR = plParcours(func(t) t.repeat(2) end, 5)
assert(plR[1] == 5 and plR[2] == 0 and plR[3] == 5 and plR[4] == 10 and plR[5] == 10)

## repeat(2, true) : les deux allers, PUIS les deux retours (+1 +1 -1 -1). Entre deux
## retours la position saute de 0 à 10, comme elle saute de 10 à 0 entre deux allers :
## chaque segment rejoue le parcours entier dans son sens.
var plRY = plParcours(func(t) t.repeat(2, true) end, 9)
assert(plRY[4] == 10 and plRY[5] == 5 and plRY[6] == 10 and plRY[8] == 0)

## Deux appels COMPOSENT : le second agit sur le plan déjà construit. repeat(nil, true)
## puis repeat(2) donne deux allers-retours (+1 -1 +1 -1).
var plYR = plParcours(func(t) t.repeat(nil, true).repeat(2) end, 9)
assert(plYR[2] == 10 and plYR[4] == 0 and plYR[6] == 10 and plYR[8] == 0)

## Les bornes sont figées au premier démarrage : écrire dans l'objet en pleine animation ne
## redéfinit pas le départ du parcours suivant (sinon un retour dériverait).
var plO = {x: 0}
var plT = tween.to(plO, {x: 10}, 1.0, "linear").repeat(2)
tween.update(0.5)
plO.x = 100
tween.update(0.5)
assert(plO.x == 0)
plT.cancel()

## `repeat()` sans compte : sans fin. Le tween ne se termine pas de lui-même, et sa
## progression est celle du tour
## courant ; `progress` d'un plan fini couvre en revanche TOUS ses segments.
var plL = {x: 0}
var plTL = tween.to(plL, {x: 10}, 1.0, "linear").repeat()
tween.update(2.25)
assert(not plTL.isDone() and math.abs(plTL.progress() - 0.25) < 0.001)
plTL.cancel()
var plF = {x: 0}
var plTF = tween.to(plF, {x: 10}, 1.0, "linear").repeat(4)
tween.update(2.0)
assert(math.abs(plTF.progress() - 0.5) < 0.001)
plTF.cancel()

## Handle périmé : garder le handle d'une animation finie est normal, les modificateurs
## doivent y être inoffensifs.
var plD = {x: 0}
var plTD = tween.to(plD, {x: 1}, 0.1, "linear")
tween.update(0.2)
assert(plTD.isDone())
plTD.repeat(3)
plTD.repeat(nil, true)
plTD.repeat(2, true)
assert(plTD.isDone())

## ── Booléens : type étanche, mais « le vide est faux » conservé ───────────────
## L'égalité doit tester les DEUX côtés du couple : un seul test aurait laissé
## `true == 1` répondre vrai par la branche numérique, et `false == false` répondre FAUX
## en tombant dans le cas par défaut (cas réellement rencontré à l'implémentation).
assert((false == false) == true)
assert((true == true) == true)
assert((true == false) == false)
assert(true <> 1 and 1 <> true)
assert(false <> 0 and 0 <> false)
assert(false <> nil and false <> "" and false <> [])

## Le type se NOMME : `typeof` avait gardé le cas par défaut « unknown » quand le booléen
## est devenu un type à part entière, si bien qu'un script ne pouvait pas le reconnaître.
assert(typeof(true) == "bool" and typeof(false) == "bool")
assert(typeof(1 < 2) == "bool" and typeof(not nil) == "bool")

## Un booléen est une CLÉ distincte de l'entier correspondant : le hachage doit séparer
## ce que l'égalité sépare, sinon les deux clés se confondraient dans la map.
var bk = {}
bk[true] = "b"
bk[1] = "i"
bk[false] = "bf"
bk[0] = "z"
assert(bk[true] == "b" and bk[1] == "i" and bk[false] == "bf" and bk[0] == "z")
assert(len(bk) == 4)

## Les producteurs de booléens : `not`, les six comparaisons, et les prédicats natifs.
assert((not nil) == true)
assert((3 > 4) == false)
assert(("a" < "b") == true)
assert(math.isNan(math.sqrt(-1)) == true)
assert(math.isInf(math.INF) == true)
assert(math.isNan(1.0) == false)

## Affichage : "true"/"false", en anglais comme les mots-clés — donc recopiable dans un
## script. Vaut aussi pour la concaténation et l'interpolation.
assert(("" + true) == "true")
assert(("" + false) == "false")
var bi = 1 == 1
assert("{bi}" == "true")

## Le booléen traverse les frontières sans se dénaturer : passage en argument, retour de
## fonction, stockage en map, en tableau, capture par une closure.
func bool_id(v)  return v  end
assert(bool_id(true) == true and bool_id(false) == false)
var bm = {ok: false}
bm.ok = 1 == 1
assert(bm.ok == true)
var ba = [true, false]
assert(ba[1] == true and ba[2] == false)
var bcap = false
func bool_set()  bcap = 2 > 1  end
bool_set()
assert(bcap == true)

## Un booléen reste un test de vérité valide partout où une valeur est attendue.
var bcount = 0
for i = 1, 3 do
    if i > 1 then bcount += 1 end
end
assert(bcount == 2)
while false do
    assert(nil)   ## jamais atteint
end

## ── data : le booléen traverse la persistance ────────────────────────────────
## Regression : `encode_value` ne connaissait que entier, flottant et chaîne, si bien que
## `data.set(k, true)` échouait dès que `true` a cessé d'être l'entier 1 — sur un message
## qui promettait pourtant le booléen. Le module n'avait aucun test de comportement.
data.set("bt", true)
data.set("bf", false)
data.set("bn", 42)
data.set("bs", "x")
assert(data.get("bt") == true)
assert(data.get("bf") == false)
assert(data.get("bn") == 42 and data.get("bs") == "x")
assert(data.has("bt") and not data.has("jamais_ecrit"))

## Le type survit à l'encodage : ce qui revient est un BOOLÉEN, pas l'entier 1.
assert(data.get("bt") <> 1)
assert(data.get("bf") <> 0)

## Valeur par défaut d'une clé absente, et suppression par nil.
assert(data.get("jamais_ecrit", "defaut") == "defaut")
data.set("bt", nil)
assert(not data.has("bt"))
data.set("bf", nil)
data.set("bn", nil)
data.set("bs", nil)

## ── tween.sequence : une suite d'étapes ──────────────────────────────────────
## La clé de temps est `delay` dans les deux rôles : durée quand l'étape porte `to`,
## attente sinon.
var sqO = {x: 0, y: 0}
var sqT = tween.sequence(sqO, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {delay: 0.5},
    {to: {y: 20}, delay: 1.0, curve: "linear"},
])
tween.update(0.5)
assert(sqO.x == 5 and sqO.y == 0)
tween.update(0.5)
assert(sqO.x == 10)
tween.update(0.5)              ## l'attente ne bouge rien
assert(sqO.x == 10 and sqO.y == 0)
tween.update(1.0)
assert(sqO.y == 20 and sqT.isDone())

## La valeur de départ d'une étape est celle que la précédente a laissée, pas celle
## qu'avait le champ à la déclaration de la séquence.
var sqE = {v: 0}
tween.sequence(sqE, [
    {to: {v: 100}, delay: 1.0, curve: "linear"},
    {to: {v: 150}, delay: 1.0, curve: "linear"},
])
tween.update(1.0)
tween.update(0.5)
assert(sqE.v == 125)
tween.cancelAll()

## Une étape peut changer d'objet par `target`.
var sqA = {x: 0}
var sqB = {x: 0}
tween.sequence(sqA, [
    {to: {x: 4}, delay: 1.0, curve: "linear"},
    {target: sqB, to: {x: 8}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(sqA.x == 4 and sqB.x == 8)

## `progress` court sur toute la suite, en TEMPS : compter les étapes franchies ferait
## sauter la progression, les durées étant inégales.
var sqP = {v: 0}
var sqPT = tween.sequence(sqP, [
    {to: {v: 1}, delay: 3.0, curve: "linear"},
    {to: {v: 2}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(math.abs(sqPT.progress() - 0.5) < 0.001)
sqPT.cancel()

## `repeat` porte sur la suite ENTIÈRE, et l'aller-retour la rejoue à l'envers, chaque
## étape inversée. Regression : un pas de temps plus grand qu'une étape la franchissait
## sans lire ses bornes, et le retour repartait alors d'une valeur fausse.
var sqR = {x: 0}
tween.sequence(sqR, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {to: {x: 30}, delay: 1.0, curve: "linear"},
]).repeat(nil, true)
tween.update(2.0)              ## un seul pas pour tout l'aller
assert(sqR.x == 30)
tween.update(0.5)
assert(sqR.x == 20)            ## retour : l'étape 2 rejouée de 30 vers 10
tween.update(0.5)
assert(sqR.x == 10)
tween.update(1.0)
assert(sqR.x == 0)             ## puis l'étape 1, de 10 vers 0
tween.cancelAll()

## Une attente seule est une séquence valide, et elle se termine.
var sqW = {v: 5}
var sqWT = tween.sequence(sqW, [{delay: 0.5}])
tween.update(0.3)
assert(sqW.v == 5 and not sqWT.isDone())
tween.update(0.3)
assert(sqWT.isDone())

## Écrasement : un tween visant le même champ annule la séquence, comme pour tween.to.
var sqX = {x: 0}
tween.sequence(sqX, [{to: {x: 100}, delay: 1.0, curve: "linear"}])
tween.to(sqX, {x: 50}, 1.0, "linear")
tween.update(1.0)
assert(sqX.x == 50 and tween.count() == 0)

## ── Module sound : oscillateurs ─────────────────────────────────────────────────
## Sans périphérique, tout l'API répond quand même : les voix existent, leurs paramètres
## se lisent et s'écrivent. Seule la sortie est muette, ce qui rend la synthèse testable
## dans un conteneur sans carte son.
var osA = sound.sine(440)
assert(osA.freq() == 440 and osA.shape() == "sine")
assert(osA.volume() == 0.5 and osA.pan() == 0)
assert(not osA.isPlaying())

## Les écritures rendent le HANDLE, donc se chaînent ; les lectures rendent la valeur.
assert(osA.freq(880).volume(0.25).pan(-1) == osA)
assert(osA.freq() == 880 and osA.volume() == 0.25 and osA.pan() == -1)

## start/stop bascule l'état, et se chaîne aussi.
osA.start()
assert(osA.isPlaying())
osA.stop()
assert(not osA.isPlaying())

## Volume et panoramique sont BORNÉS en silence, comme le volume général.
assert(osA.volume(5) == osA and osA.volume() == 1)
assert(osA.pan(-9) == osA and osA.pan() == -1)
assert(osA.pan(9) == osA and osA.pan() == 1)

## Chaque raccourci fixe sa forme d'onde, et `shape` la relit par son nom.
assert(sound.square(100).shape() == "square")
assert(sound.saw(100).shape() == "saw")
assert(sound.triangle(100).shape() == "triangle")
assert(sound.noise().shape() == "noise")
assert(sound.osc(220, "square").shape() == "square")

## La forme se change en marche, comme la fréquence.
assert(osA.shape("saw").shape() == "saw")

## Recyclage : quand la table est pleine, la voix arrêtée la PLUS ANCIENNE est reprise —
## un rang de création, et non le premier slot venu, qui martelait toujours le même. Le
## handle repris est détecté comme périmé au lieu de désigner la voix du suivant.
var osVieux = sound.sine(200)
var osNeuf = nil
for i = 1, 20 do
    osNeuf = sound.sine(300)
end
var osPerime = false
try
    osVieux.freq()
catch e
    osPerime = true
end
assert(osPerime and osNeuf.freq() == 300)

## Enveloppe : portée par l'oscillateur, pas par un objet séparé (p5 en a un parce qu'il
## peut moduler n'importe quel paramètre ; ici la cible est unique). La lecture rend une map.
var osE = sound.sine(440)
assert(osE.envelope().attack == 0.01 and osE.envelope().sustain == 0.7)
assert(osE.envelope(0.02, 0.1, 0.5, 0.3) == osE)
var envE = osE.envelope()
assert(envE.attack == 0.02 and envE.decay == 0.1 and envE.sustain == 0.5 and envE.release == 0.3)

## trigger rend la voix audible, release la lâche — l'extinction, elle, appartient au
## mélangeur (donc au navigateur : le conteneur d'intégration n'a pas de sortie). La forme
## de la courbe est vérifiée par les tampons, qui appliquent la MÊME fonction.
assert(not osE.isPlaying())
assert(osE.trigger(0.2) == osE and osE.isPlaying())
assert(osE.release() == osE)

## Sans enveloppe, un oscillateur se comporte comme avant son introduction : start/stop seuls.
var osSansE = sound.saw(100)
assert(osSansE.start().isPlaying())
osSansE.stop()

## ── Module sound : tampons calculés ─────────────────────────────────────────────
## Un tampon est un son CALCULÉ une fois puis déclenché. Ses accesseurs sont ce qui rend la
## synthèse vérifiable sans carte son : on lit les échantillons au lieu de les écouter.
var bufT = sound.tone(1, 1.0)
assert(math.abs(bufT.duration() - 1.0) < 0.001)
assert(math.abs(bufT.peak() - 1.0) < 0.001)

## Un sinus à 1 Hz sur une seconde passe par 0, +1, 0, -1 aux quarts de tour : c'est la
## forme même de l'onde qui est contrôlée, pas seulement la présence d'un tampon.
assert(math.abs(bufT.sample(0)) < 0.001)
assert(math.abs(bufT.sample(0.25) - 1.0) < 0.001)
assert(math.abs(bufT.sample(0.5)) < 0.001)
assert(math.abs(bufT.sample(0.75) + 1.0) < 0.001)

## Hors du tampon, l'échantillon vaut zéro — le silence qui l'entoure, plutôt qu'une erreur.
assert(bufT.sample(-1) == 0 and bufT.sample(99) == 0)

## sound.generate échantillonne une FORMULE Ollin, une seule fois, hors du rappel audio.
var bufG = sound.generate(0.5, func(t) return 0.5 end)
assert(math.abs(bufG.duration() - 0.5) < 0.001)
assert(math.abs(bufG.peak() - 0.5) < 0.001)
assert(math.abs(bufG.sample(0.1) - 0.5) < 0.001)

## Une valeur hors de [-1;1] est ramenée dans la plage : au-delà, la sortie saturerait.
assert(math.abs(sound.generate(0.1, func(t) return 5 end).peak() - 1.0) < 0.001)

## Enveloppe appliquée aux échantillons : c'est la MÊME fonction que celle du mélangeur, donc
## ce test valide aussi la courbe des oscillateurs — que rien d'autre ne peut contrôler ici.
var bufE = sound.generate(1.0, func(t) return 1 end)
bufE.envelope(0.1, 0.2, 0.5, 0.25)
assert(math.abs(bufE.sample(0.05) - 0.5) < 0.01)    ## mi-attaque
assert(math.abs(bufE.sample(0.1) - 1.0) < 0.01)     ## sommet de l'attaque
assert(math.abs(bufE.sample(0.2) - 0.75) < 0.01)    ## mi-déclin, entre 1 et le maintien
assert(math.abs(bufE.sample(0.5) - 0.5) < 0.01)     ## maintien
assert(bufE.sample(0.999) < 0.01)                   ## relâchement fini avec le son

## Lecture : play/stop, et les réglages se chaînent comme ceux d'un oscillateur.
assert(not bufE.isPlaying())
assert(bufE.play().isPlaying())
assert(bufE.volume(0.3).pan(0.5).rate(2).volume() == 0.3)
assert(bufE.pan() == 0.5 and bufE.rate() == 2)
assert(bufE.loop() == bufE)
bufE.stop()
assert(not bufE.isPlaying())

## Notes nommées : le tempérament égal autour du la 440, sans table de fréquences recopiée.
## Un NOM est accepté partout où une fréquence l'est — un seul point de passage dans le
## moteur couvre donc sound.osc, sound.tone et osc.freq.
assert(math.abs(sound.note("A4") - 440.0) < 0.01)
assert(math.abs(sound.note("a4") - 440.0) < 0.01)      ## la casse est libre
assert(math.abs(sound.note("C4") - 261.626) < 0.01)
assert(math.abs(sound.note("A0") - 27.5) < 0.01)
assert(math.abs(sound.note("C-1") - 8.1758) < 0.001)   ## octave la plus grave

## Dièse et bémol donnent la même hauteur quand ils désignent la même note.
assert(math.abs(sound.note("C#4") - sound.note("Db4")) < 0.001)

## Les trois usages d'une fréquence acceptent le nom.
assert(math.abs(sound.osc("A4").freq() - 440.0) < 0.01)
assert(math.abs(sound.sine(100).freq("E4").freq() - 329.628) < 0.01)
assert(math.abs(sound.tone("A5", 0.1).duration() - 0.1) < 0.001)

## ── Module touch (multitouche) ──────────────────────────────────────────────────
## Sans surface tactile — c'est le cas du conteneur d'intégration — le module existe quand
## même : un script qui lit l'état tourne sans rien voir, au lieu d'échouer sur un nil.
assert(typeof(touch) == "map")
assert(touch.count() == 0)
assert(typeof(touch.points()) == "array" and #touch.points() == 0)

## Les rappels s'affectent comme ceux de `mouse` : le moteur appelle ce qui existe, et
## l'absence des trois n'est pas une faute.
global tcVus = []
func touch.began(id, x, y)
    tcVus[#tcVus + 1] = id
end
assert(#tcVus == 0)

## ── Module audio (session) ──────────────────────────────────────────────────────
## Le module existe TOUJOURS, même sans périphérique : la génération d'ondes est un pur
## calcul, et la suite tourne dans un conteneur sans carte son. Seule la sortie est muette.
assert(typeof(audio) == "map")
assert(audio.sampleRate() == 44100)

## Sans périphérique, start() rend false et isReady() reste false — sans lever.
var auPret = audio.start()
assert(typeof(auPret) == "bool")
assert(audio.isReady() == auPret)

## Le volume se relit tel qu'il a été posé, et se borne à [0;1] en silence : au-delà la
## sortie saturerait, donc on corrige au lieu de refuser (comme une composante couleur).
assert(audio.volume(0.25) == 0.25)
assert(audio.volume() == 0.25)
assert(audio.volume(9) == 1)
assert(audio.volume(-3) == 0)
audio.volume(1)

## La pause appartient à la SESSION : elle suspend l'AVANCEMENT du mélange, là où un volume
## à zéro laisserait tout courir en silence et ferait reprendre le son plus loin.
assert(not audio.isPaused())
audio.pause()
assert(audio.isPaused())
audio.resume()
assert(not audio.isPaused())

## Égalité par IDENTITÉ des types référence. Seules les maps étaient couvertes : deux
## variables désignant le même tableau se comparaient fausses, et `a <> a` était vrai.
var idTab = [1, 2]
var idTabAlias = idTab
assert(idTab == idTabAlias)
assert(not (idTab <> idTabAlias))
assert(idTab <> [1, 2])          ## contenu identique, objets distincts
var idRange = [1;5]
var idRangeAlias = idRange
assert(idRange == idRangeAlias)
assert(idRange <> [1;5])
func idFonc()
end
var idFoncAlias = idFonc
assert(idFonc == idFoncAlias)
assert(idFonc <> print)
func faireFerm(n)
    return func() return n end
end
var idFerm = faireFerm(1)
var idFermAlias = idFerm
assert(idFerm == idFermAlias)
assert(idFerm <> faireFerm(1))   ## deux closures distinctes de la même fonction
## Un tableau n'est pas égal à une map, ni à un nombre — mais 1 et 1.0 restent égaux.
assert(idTab <> {})
assert(idTab <> 1)
assert(1 == 1.0)

## `free()` rend la voix au moteur ET périme le handle : le réutiliser doit être signalé, pas
## silencieux. Sans cette libération explicite, tout script polyphonique devait pré-allouer un
## pool, faute de savoir quand un slot arrêté serait recyclé.
var oscLibre = sound.sine(440)
oscLibre.free()
var perime = false
try
    oscLibre.freq(880)
catch e
    perime = true
end
assert(perime)
## Une voix rendue SANS enveloppe est libre tout de suite : on peut en créer autant que la
## table en compte, l'une après l'autre.
for i = 1, 40 do
    sound.sine(220 + i).free()
end
## Un slot n'est protege que si quelque chose le fait SONNER. Sans sortie audio — build headless,
## ou navigateur avant le premier geste — aucune enveloppe ne s'acheve jamais, donc une voix rendue
## par free() doit redevenir disponible immediatement : sinon la 17e creation echouait sur
## « no oscillator available », alors que chaque voix avait bien ete liberee.
for i = 1, 20 do
    var v = sound.sine(330 + i).envelope(0.01, 0.05, 0.5, 5.0)
    v.trigger(0.05)
    v.free()
end
var autre = sound.sine(660)
assert(autre.isPlaying() == false)
autre.free()

print("regressions ok")
