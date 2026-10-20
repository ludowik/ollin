## Regression tests — The core: constants, values, builtins, memory, the engine globals.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/core.ol — it must finish without error.

## ── chunk: constant dedup is STRICT about types ─────────────────────────────
## int 0, float 0.0 and nil share the same zero bits but carry distinct tags, so they must NOT
## be merged in the pool (nil would otherwise become 0, and so on).
var ck_i = 0
var ck_f = 0.0
var ck_n = nil
assert(not (ck_i == ck_n))   ## the int 0 is not nil
assert(not (ck_f == ck_n))   ## the float 0.0 is not nil
assert(ck_i == ck_f)         ## 0 == 0.0 numerically: two distinct constants, but equal
assert(ck_n == nil)
## identical strings are deduped: the same interned content, a single pool entry
var ck_s1 = "dup-const"
var ck_s2 = "dup-const"
assert(ck_s1 == ck_s2)

## ── value: num_value no longer casts undefined behaviour on a non-finite or out-of-range value
## (math.* can produce inf and nan, and a huge float literal exceeds int64)
assert(math.exp(1000) > 1000000000000000000)   ## inf stays a float, and stays comparable
assert(math.sqrt(-1) <> math.sqrt(-1))          ## nan is not nan: it stays a float nan
var big_f = 100000000000000000000.5
assert(big_f > 1000000000000000000)             ## ~1e20 stays a float, with no undefined cast

## ── a static builtin: the class and instance forms agree (as a Ollin `static func` does) ──
## A builtin declared static does not receive self, so its first parameter sits in R[0] whether
## the call is on the class or on an instance (before, self was injected on an instance, the
## parameter was shifted, and the argument was read wrongly).
var col_a = Color.gray(0.5)              ## a parameterised static factory, on the class
assert(col_a.r == 0.5 and col_a.b == 0.5)
var col_c = Color(1, 0, 0)
var col_b = col_c.gray(0.25)            ## the SAME method, on an instance: the parameter sits in R[0]
assert(col_b.r == 0.25 and col_b.g == 0.25)
assert(Color.random().a == 1 and col_c.random().a == 1)  ## a static random, in both modes

## mem(): the heap memory in use, in bytes, as an integer — it grows with the allocations
assert(typeof(mem()) == "int")
assert(mem() > 0)
var mem_before = mem()
var big = []
for i = 1, 20000 do
    big[i] = i
end
assert(mem() >= mem_before)     ## allocating a big array did not lower the memory

## The engine globals: CX and CY are the CENTRE of the render area, not its size — the point of
## the rename from CW/CH, which read as "canvas width" right next to W. The relation holds in every
## build, including this headless one where the area is 0 by 0.
assert(CX == W / 2)
assert(CY == H / 2)
## SIZE is min(W, H) — a size that fits either dimension, for a square drawn on a non-square area
var expected_size = W
if H < W then
    expected_size = H
end
assert(SIZE == expected_size)

## ── Color.grayscale and Color.pastel: new colours, the alpha kept ──
## Neither method was called by any test.
var colOrig = Color(1, 0, 0, 0.5)
var colGray = colOrig.grayscale()
assert(colGray.r == colGray.g and colGray.g == colGray.b, "a grey has three equal components")
assert(math.abs(colGray.r - 0.299) < 0.000001, "the luminance of Rec. 601: 0.299 for pure red")
assert(colGray.a == 0.5, "the alpha is kept")
assert(math.abs(Color(1, 1, 1).grayscale().r - 1) < 0.000001 and Color(0, 0, 0).grayscale().r == 0, "white stays white, black stays black")
var colSoft = colOrig.pastel()
assert(colSoft.r == 1 and colSoft.g == 0.5 and colSoft.b == 0.5 and colSoft.a == 0.5, "half way to white, the alpha kept")
assert(Color(0, 0, 0).pastel().r == 0.5)
assert(colOrig.r == 1 and colOrig.g == 0 and colOrig.a == 0.5, "the colour itself does not change")
assert(colGray.pastel().a == 0.5 and colSoft.grayscale().__class__ == colOrig.__class__, "the results are colours too, of the same class")
