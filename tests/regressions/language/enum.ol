## Regression tests — Enumerations.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/enum.ol — it must finish without error.

## ── enum ────────────────────────────────────────────────────────────────────
## Numbering: 1 by default, then +1 each time; an integer literal redefines what follows; a
## non-literal value — here a string — leaves the counter where it is.
enum RgState IDLE = 0, WALK, JUMP = 10, FALL end
assert(RgState.IDLE == 0 and RgState.WALK == 1)
assert(RgState.JUMP == 10 and RgState.FALL == 11)
enum RgMix A, B = "text", C end
assert(RgMix.A == 1 and RgMix.B == "text" and RgMix.C == 2)
enum RgNeg X = -3, Y end
assert(RgNeg.X == -3 and RgNeg.Y == -2)
enum RgAlias UN = 1, FIRST = 1 end       ## a repeated value is an alias, and is allowed
assert(RgAlias.UN == RgAlias.FIRST)

## For READING, an enum is an ordinary map: len, iteration, and values of any type.
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

## The freeze is SHALLOW: the enum refuses a write, the object it holds does not.
RgObj.L[1] = 99
assert(RgObj.L[1] == 99)

## The lock at run time: an alias and a computed key both go through the same SET_INDEX.
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

## an enum into an existing map, the `a.b` form.
global rgCfg = {}
enum rgCfg.mode PLEIN, FENETRE end
assert(rgCfg.mode.PLEIN == 1 and rgCfg.mode.FENETRE == 2)

## Pool recycling: the enum marking must not contaminate a reused map. The maps below are freed,
## then their memory is handed out again.
for i = 1, 200 do
    var rg_tmp = {a: i}
    rg_tmp.a = i + 1
    assert(rg_tmp.a == i + 1)
end
var rg_libre = {}
rg_libre.x = 1
assert(rg_libre.x == 1)


## An enum's freeze holds its CONTENT, not its NAME: the name is an ordinary global, as a class's
## is, so it can be reassigned. Writing an ELEMENT stays refused (test_errors.sh).
func checkEnumNameIsOrdinary()
    assert(RgCol.A == 1)
    RgCol = 5
    assert(RgCol == 5)
end
enum RgCol
    A, B
end
checkEnumNameIsOrdinary()

## An enum member with a literal value is read as a CONSTANT, the compiler knowing the value.
## The fold is invisible, so what is pinned here is everything that must NOT fold: a name
## shadowed by a local, a member holding an object or a function, an enum declared where the
## statement may never run, and a name that is reassigned (checked above by
## checkEnumNameIsOrdinary, whose RgCol is both declared twice and reassigned).
enum FoState IDLE = 0, WALK, JUMP = 10 end
assert(FoState.IDLE == 0 and FoState.WALK == 1 and FoState.JUMP == 10)

func foShadowed()
    var FoState = [nil, 99]    ## a local of the same name is a DIFFERENT variable
    return FoState[2]
end
assert(foShadowed() == 99)

func foSquare(x) return x * x end
enum FoMixed N = 4, F = foSquare, L = [7, 8] end
assert(FoMixed.N == 4)         ## literal: folded
assert(FoMixed.F(6) == 36)     ## a function stays a real lookup
assert(FoMixed.L[2] == 8)      ## so does an array

func foDeferred()
    enum FoLate A = 1 end      ## declared inside a function: it may never run, so no fold
end
var foReached = 0
try
    foReached = FoLate.A       ## still fails, exactly as before
catch err
    foReached = -1
end
assert(foReached == -1)
foDeferred()
assert(FoLate.A == 1)          ## and once it HAS run, the ordinary lookup finds it
