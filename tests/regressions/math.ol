## Regression tests — The math module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/math.ol — it must finish without error.

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
