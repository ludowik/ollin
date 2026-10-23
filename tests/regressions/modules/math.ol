## Regression tests — The math module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/math.ol — it must finish without error.

## ── math: int consistency (clamp, pow and logn folded as MATH1 and min/max), plus map and 0 ──
assert(typeof(math.clamp(5, 0, 10)) == "int")   ## before: a float
assert(math.clamp(5, 0, 10) == 5)
assert(typeof(math.pow(2, 3)) == "int" and math.pow(2, 3) == 8)
assert(typeof(math.pow(2, 0.5)) == "float")     ## a non-integer stays a float
assert(typeof(math.logn(8, 2)) == "int" and math.logn(8, 2) == 3)
assert(math.map(5, 2, 2, 7, 99) == 7)           ## a zero input range gives out_lo, and no inf or nan
assert(not math.isInf(math.map(5, 2, 2, 0, 10)))
assert(math.map(5, 0, 10, 0, 100) == 50)
## math.map CLAMPS x to the input range before interpolating — a value outside [in_lo, in_hi]
## saturates at the matching output bound instead of extrapolating past it.
assert(math.map(-10, 0, 100, 0, 1) == 0)
assert(math.map(150, 0, 100, 0, 1) == 1)
## the input range can run EITHER direction (in_lo > in_hi is legal, a descending scale): the
## clamp follows the ordered bounds, not in_lo specifically.
assert(math.map(-5, 10, 0, 0, 100) == 100)
assert(math.map(15, 10, 0, 0, 100) == 0)

## ── math: the inverse trigonometric functions, the logarithms in base 2 and 10, the angle units, frac ──
## Not one of them was called by any test. Compared to a tolerance: a float result is rarely exact.
func mathNear(a, b)
    return math.abs(a - b) < 0.000000001
end
assert(math.tan(0) == 0 and mathNear(math.tan(math.PI / 4), 1))
assert(mathNear(math.asin(1), math.PI / 2) and mathNear(math.asin(-1), -math.PI / 2) and math.asin(0) == 0)
assert(math.acos(1) == 0 and mathNear(math.acos(0), math.PI / 2) and mathNear(math.acos(-1), math.PI))
assert(math.atan(0) == 0 and mathNear(math.atan(1), math.PI / 4))
## atan2(y, x) takes the quadrant into account, which atan(y / x) cannot
assert(mathNear(math.atan2(1, 1), math.PI / 4) and mathNear(math.atan2(-1, -1), -3 * math.PI / 4))
assert(mathNear(math.atan2(0, -1), math.PI) and mathNear(math.atan2(1, 0), math.PI / 2))
## out of the domain: nan, not an error
assert(math.isNan(math.asin(2)) and math.isNan(math.acos(2)))
assert(math.log2(8) == 3 and math.log2(1) == 0 and mathNear(math.log2(10), 3.321928094887362))
assert(math.log10(1000) == 3 and math.log10(1) == 0 and mathNear(math.log10(2), 0.3010299956639812))
assert(math.isInf(math.log2(0)) and math.log2(0) < 0 and math.isNan(math.log10(-1)))
## degrees and radians
assert(mathNear(math.deg(math.PI), 180) and math.deg(0) == 0 and mathNear(math.rad(180), math.PI) and mathNear(math.rad(90), math.PI / 2))
assert(mathNear(math.deg(math.rad(37)), 37))
## frac is x - floor(x): the part after the point, which stays positive for a negative number
assert(math.frac(2.75) == 0.75 and math.frac(-2.75) == 0.25 and math.frac(3) == 0 and math.frac(0.5) == 0.5)

## math.trunc drops the fractional part toward zero (floor would go the other way for a negative number)
assert(math.trunc(2.7) == 2 and math.trunc(-2.7) == -2 and math.trunc(5) == 5 and math.trunc(-0.5) == 0)
assert(typeof(math.trunc(2.7)) == "int")
## math.seed makes the random numbers repeat: the same seed gives the same sequence
math.seed(7)
var mathRandA = math.rand()
var mathRandB = math.randInt(1, 1000)
math.seed(7)
assert(math.rand() == mathRandA and math.randInt(1, 1000) == mathRandB)
math.seed(8)
assert(math.rand() <> mathRandA, "another seed, another sequence")

## ── math.min / math.max with a float among the arguments, and the forms of rand, randInt and noise ──
## All integers stay integers; one float makes the result a float of the same value.
assert(math.min(2, 1.5, 3) == 1.5 and math.max(2, 2.5) == 2.5)
assert(math.min(3.5) == 3.5 and math.max(3.5) == 3.5, "a single argument is its own minimum and maximum")
assert(math.min(5, 2.0, 9) == 2 and math.max(1, 7.0, 3) == 7)

## rand(n) is in [0, n[ and rand(lo, hi) in [lo, hi[.
for i = 1, 200 do
    var one = math.rand(10)
    var two = math.rand(5, 6)
    assert(one >= 0 and one < 10, "rand(n) is in [0, n[")
    assert(two >= 5 and two < 6, "rand(lo, hi) is in [lo, hi[")
end

## randInt(n) is in [1, n], randInt(lo, hi) in [lo, hi], and a one-value range has one answer.
for i = 1, 200 do
    var one = math.randInt(3)
    var two = math.randInt(-2, 2)
    assert(one >= 1 and one <= 3 and typeof(one) == "int")
    assert(two >= -2 and two <= 2 and typeof(two) == "int")
end
assert(math.randInt(1) == 1 and math.randInt(7, 7) == 7)

## noise takes one, two or three coordinates and always answers in [0, 1].
for i = 0, 50 do
    var n1 = math.noise(i * 0.37)
    var n2 = math.noise(i * 0.37, i * 0.11)
    var n3 = math.noise(i * 0.37, i * 0.11, i * 0.53)
    assert(n1 >= 0 and n1 <= 1 and n2 >= 0 and n2 <= 1 and n3 >= 0 and n3 <= 1)
end
assert(math.noise(0.3, 0.7) == math.noise(0.3, 0.7), "the same point gives the same value")
assert(math.noise(0.3) <> math.noise(0.3, 0.7), "a second coordinate is not ignored")

## the natural logarithm, and its inverse
assert(math.log(1) == 0 and math.abs(math.log(math.exp(1)) - 1) < 1e-12)
