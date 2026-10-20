## Regression tests — The map module and the map pseudo-methods.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/map.ol — it must finish without error.

## map.len(): the built-in `len` pseudo-method really does receive the map as self (maps do not
## inject self otherwise — a module against a pseudo-method)
var mlen = {a: 1, b: 2, c: 3}
assert(mlen.len() == 3)
mlen["d"] = 4
assert(mlen.len() == 4)
assert({}.len() == 0)
var mlen_def = {len: 42}          ## a defined "len" entry wins over the builtin
assert(mlen_def.len == 42)

## The `map` module: the free-function form of what indexing and iteration already do, usable on
## any map or instance (map.len is redundant with .len()/#, kept for symmetry with math/string).
var mm = {x: 1, y: 2, z: 3}
assert(map.len(mm) == 3)
assert(map.has(mm, "y") and not map.has(mm, "w"))
assert(map.keys(mm).len() == 3 and map.values(mm).len() == 3)
assert(map.delete(mm, "y") == 2)       ## returns the removed value
assert(map.delete(mm, "y") == nil)     ## already gone: nil, not an error
assert(mm.len() == 2 and not map.has(mm, "y"))
## a frozen enum refuses map.delete exactly as it refuses `E.A = v` (op_SET_INDEX)
enum MapDelEnum
    A, B
end
var enum_del_err = false
try
    map.delete(MapDelEnum, "A")
catch e
    enum_del_err = true
end
assert(enum_del_err)

## The same five work as pseudo-methods too (`m.keys()`), sharing the SAME functions as the
## module form — CALL_METHOD recognizes them by function pointer (is_map_module_fn), restricted
## to a PLAIN map or enum (never an instance — same rule `len` always had).
var pm = {p: 1, q: 2}
assert(pm.len() == map.len(pm))
assert(pm.keys().len() == map.keys(pm).len())
assert(pm.has("p") == map.has(pm, "p"))
assert(pm.delete("p") == 1)
assert(not pm.has("p"))
class NoFallback
    func init()
        self.a = 1
    end
end
var nf_err = false
try
    NoFallback().keys()
catch e
    nf_err = true
end
assert(nf_err)     ## an instance never gets the map module's fallback, same as len

## `map.len(m)` must read `m`, not `map` itself: `len` is a REAL key of the `map` module (found in
## its own data, not through the fallback), so `map.len(m)` parses as a method call on `map` — and
## without excluding a MODULE receiver from self-injection, `map` would be injected as self and
## `m` would slide into an unwanted second argument. Bisected against a real regression: this once
## returned map.len() (5, the module's own five keys) instead of m.len().
var mlm = {j: 1, k: 2, l: 3}
assert(map.len(mlm) == mlm.len())
assert(map.len(mlm) == 3)

## the module form also accepts a CLASS object itself (T_CLASS, not an instance) — same layout as
## a map, so its own fields (__name__, its methods) are listable the same way
class MapOnClass
    func init()
    end
    func greet()
    end
end
assert(map.has(MapOnClass, "__name__"))
assert(map.keys(MapOnClass).contains("greet"))

## storing an UNRELATED builtin under a map's own key must keep calling it plainly — is_map_module_fn
## excludes it (math.sin is none of the five), so no self is injected regardless of the receiver
var stored = {f: math.sin}
assert(stored.f(0) == 0)
