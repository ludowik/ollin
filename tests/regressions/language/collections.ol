## Regression tests — Collections as types: map keys, ranges, nil removal, typeof of a module, equality by identity.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/collections.ol — it must finish without error.

## ── map: classes, ranges and builtins can serve as keys ────────────────────
## (before: ValueEqual returned false by default for T_CLASS, T_BUILTIN and T_RANGE, so the key
## inserted was never found again)
class MK_A end
class MK_B end
global mk = {}
mk[MK_A] = 1
mk[MK_B] = 2
assert(mk[MK_A] == 1)
assert(mk[MK_B] == 2)          ## two distinct classes are two distinct keys
var mk_r = [1; 5]
mk[mk_r] = 7
assert(mk[mk_r] == 7)          ## a range as a key
mk[print] = 9
assert(mk[print] == 9)         ## a builtin as a key
## an int and a whole float stay the SAME key (1 == 1.0) — hash and equal agree
global mk2 = {}
mk2[1] = 10
assert(mk2[1.0] == 10)
## a WHOLE float key beyond the int64 range (before, ValueHash cast to int64, which is undefined
## behaviour and traps on WASM). It must work like any other key.
var mk_huge = math.pow(2.0, 100)     ## 2^100: a float, integral, far beyond 2^63
mk2[mk_huge] = 42
assert(mk2[mk_huge] == 42)
mk2[-mk_huge] = 43
assert(mk2[-mk_huge] == 43)

## ── range: non-finite bounds refused, plus iteration (the devirtualised iterator path) ──
## (before: MAKE_RANGE and FOR_PREP accepted inf and NaN, hence endless iteration, hence a freeze)
global rng_c1 = "none"
try
    for i = 0.0, math.exp(1000) do break end   ## a numeric for, with +inf as the bound
catch e
    rng_c1 = "x"
end
assert(rng_c1 == "x")                          ## it must throw, not loop
global rng_c2 = "none"
try
    var rng_bad = ]0; math.exp(1000)]          ## an open range (MAKE_RANGE) with a +inf bound
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
for i in ]1; 5] do rng_s += i end              ## left-open, hence the range iterator, devirtualised
assert(rng_s == 14)                            ## 2+3+4+5
var rng_r = [1; 4]
var rng_t = 0
for i in rng_r do rng_t += i end               ## a range value, hence the range iterator
assert(rng_t == 10)                            ## 1+2+3+4

## A nil value REMOVES the key (Map::set) instead of leaving a "present but nil" ghost entry that
## used to inflate len() and show up in a for..in walk.
var mdel = {a: 1, b: 2}
mdel.a = nil
assert(mdel.len() == 1)
var mdel_seen = []
for k, v in mdel do
    mdel_seen.push(k)
end
assert(mdel_seen.join(",") == "b")     ## "a" is gone, not walked as a nil-valued entry
mdel["b"] = nil
assert(mdel.len() == 0)
mdel["never-there"] = nil              ## erasing an absent key is a harmless no-op
assert(mdel.len() == 0)

## typeof distinguishes a built-in module from a plain map, now that Map::kind marks the root
## object of a module (never propagated to whatever the module contains)
assert(typeof(math) == "module")
assert(typeof(map) == "module")
assert(typeof({}) == "map")
assert(typeof({j: 1, k: 2, l: 3}) == "map")          ## whatever the module holds is a plain map again

## Equality by IDENTITY for the reference types. Only maps were covered: two variables naming the
## same array compared as unequal, and `a <> a` was true.
var idTab = [1, 2]
var idTabAlias = idTab
assert(idTab == idTabAlias)
assert(not (idTab <> idTabAlias))
assert(idTab <> [1, 2])          ## same contents, distinct objects
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
assert(idFerm <> faireFerm(1))   ## two distinct closures of the same function
## An array equals neither a map nor a number — but 1 and 1.0 stay equal.
assert(idTab <> {})
assert(idTab <> 1)
assert(1 == 1.0)
