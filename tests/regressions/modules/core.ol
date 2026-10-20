## Regression tests — The core module: mem and the engine globals.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/core.ol — it must finish without error.

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
