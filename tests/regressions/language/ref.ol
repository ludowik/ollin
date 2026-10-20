## Regression tests — Passing by reference (ref).
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/ref.ol — it must finish without error.

## ── ref (passing by reference) ──────────────────────────────────────────────
## `ref x` is desugared by the parser into {__ref, get, set}: two closures that read and write
## the target. The upvalues do the work, a local included.
global rfGlobal = 5
var rfLocal = 1
global rfObj = {field: "a", sub: {x: 1}}

func rfLire(r) return r.get() end
func rfWrite(r, v) r.set(v) end

assert((ref rfGlobal).__ref)              ## the validation mark, for the native modules
assert(rfLire(ref rfGlobal) == 5)
rfWrite(ref rfGlobal, 42)
assert(rfGlobal == 42)
rfWrite(ref rfLocal, 7)                 ## writing a LOCAL from another function
assert(rfLocal == 7)
rfWrite(ref rfObj.field, "b")
assert(rfObj.field == "b")
rfWrite(ref rfObj.sub.x, 99)            ## a path two levels deep
assert(rfObj.sub.x == 99)

## The generated setter's parameter must NEVER shadow the target: in a naive version `ref v`
## produced `func(v) v = v end`, hence a write with no effect.
var v = 1
rfWrite(ref v, 9)
assert(v == 9)

## A reference is an ordinary value: it can be stored and passed on.
var rfStock = ref rfGlobal
rfStock.set(3)
assert(rfGlobal == 3)

## A reference taken on a BLOCK local: readable after the block ends, the upvalue having been
## closed over a copy, and a write no longer reaches anything — behaviour frozen here so that a
## change to the upvalue mechanism shows up.
var rfEscaped = nil
do
    var rfInner = "inside"
    rfEscaped = ref rfInner
end
assert(rfEscaped.get() == "inside")
