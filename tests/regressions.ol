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

print("regressions ok")
