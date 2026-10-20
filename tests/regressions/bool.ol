## Regression tests — Booleans.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/bool.ol — it must finish without error.

## ── Booleans: a sealed type, but "empty is false" is kept ──────────────────
## Equality must test BOTH sides of the pair: testing only one would have let `true == 1` answer
## true through the numeric branch, and `false == false` answer FALSE by falling into the default
## case — which really did happen during the implementation.
assert((false == false) == true)
assert((true == true) == true)
assert((true == false) == false)
assert(true <> 1 and 1 <> true)
assert(false <> 0 and 0 <> false)
assert(false <> nil and false <> "" and false <> [])

## The type has a NAME: `typeof` had kept its "unknown" default when the boolean became a type of
## its own, so a script could not recognise it.
assert(typeof(true) == "bool" and typeof(false) == "bool")
assert(typeof(1 < 2) == "bool" and typeof(not nil) == "bool")

## A boolean is a KEY distinct from the matching integer: the hash must separate what equality
## separates, or the two keys would merge inside the map.
var bk = {}
bk[true] = "b"
bk[1] = "i"
bk[false] = "bf"
bk[0] = "z"
assert(bk[true] == "b" and bk[1] == "i" and bk[false] == "bf" and bk[0] == "z")
assert(len(bk) == 4)

## What produces booleans: `not`, the six comparisons, and the native predicates.
assert((not nil) == true)
assert((3 > 4) == false)
assert(("a" < "b") == true)
assert(math.isNan(math.sqrt(-1)) == true)
assert(math.isInf(math.INF) == true)
assert(math.isNan(1.0) == false)

## Display: "true" and "false", in English like the keywords, hence copyable straight into a
## script. The same holds for concatenation and interpolation.
assert(("" + true) == "true")
assert(("" + false) == "false")
var bi = 1 == 1
assert("{bi}" == "true")

## A boolean crosses every boundary unaltered: passed as an argument, returned from a function,
## stored in a map or an array, captured by a closure.
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

## A boolean stays a valid truth test wherever a value is expected.
var bcount = 0
for i = 1, 3 do
    if i > 1 then bcount += 1 end
end
assert(bcount == 2)
while false do
    assert(nil)   ## never reached
end
