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

## The same work as pseudo-methods too (`m.keys()`), sharing the SAME functions as the
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
## returned map.len() (the count of the module's own keys) instead of m.len().
var mlm = {j: 1, k: 2, l: 3}
assert(map.len(mlm) == mlm.len())
assert(map.len(mlm) == 3)

## the module form also accepts a CLASS object itself (T_CLASS, not an instance) — same layout as
## a map, so its own fields (its methods) are listable the same way — and only those: the name of a class is no field
class MapOnClass
    func init()
    end
    func greet()
    end
end
assert(map.has(MapOnClass, "init") and not map.has(MapOnClass, "__name__"))
assert(map.len(MapOnClass) == 2)
assert(map.keys(MapOnClass).contains("greet"))

## storing an UNRELATED builtin under a map's own key must keep calling it plainly — is_map_module_fn
## excludes it (math.sin is none of them), so no self is injected regardless of the receiver
var stored = {f: math.sin}
assert(stored.f(0) == 0)

## copy is a SHALLOW copy into a new, ordinary map; it works as a pseudo-method and as the module form.
var mcSrc = {a: 1, b: [1, 2]}
var mcDup = mcSrc.copy()
assert(mcDup.len() == 2 and mcDup.a == 1)
mcDup.a = 5
mcDup.c = 3
assert(mcSrc.a == 1 and not mcSrc.has("c"))        ## the original is left alone
mcSrc.b.push(3)
assert(#mcDup.b == 3)                              ## what the values hold is shared
assert(map.copy(mcSrc).len() == 2 and map.copy({}).len() == 0)
assert(map.copy(mcSrc) <> mcSrc)

## a frozen enum copies into a map that can be written
enum McColor
    RED,
    GREEN
end
var mcEnum = McColor.copy()
mcEnum.BLUE = 3
assert(mcEnum.BLUE == 3 and mcEnum.RED == 1 and not McColor.has("BLUE"))

## an instance keeps its class (an instance is never served the pseudo-methods, so the module form is the way in)
class McPoint
    func init(x, y)
        self.x = x
        self.y = y
    end
    func sum()
        return self.x + self.y
    end
end
var mcPoint = McPoint(1, 2)
var mcPointDup = map.copy(mcPoint)
mcPointDup.x = 10
assert(instanceOf(mcPointDup, McPoint) and mcPointDup.sum() == 12 and mcPoint.sum() == 3)
assert(not instanceOf(map.copy({x: 1}), McPoint))

## clear empties the map ITSELF and returns it: whoever else holds it sees it empty, and a cached read sees it too.
var mkMap = {x: 1, y: 2}
var mkAlias = mkMap
func mkRead(m)
    return m.x
end
assert(mkRead(mkMap) == 1 and mkRead(mkMap) == 1)      ## the same site read twice, so it is cached
assert(mkMap.clear() == mkMap and #mkAlias == 0 and not mkMap.has("x"))
assert(mkRead(mkMap) == nil)
mkMap.z = 3
assert(#mkAlias == 1 and map.clear({}).len() == 0)
## an instance keeps its class, only its fields go
class MkPoint
    func init()
        self.q = 1
    end
    func hi()
        return "hi"
    end
end
var mkPoint = MkPoint()
map.clear(mkPoint)
assert(mkPoint.q == nil and mkPoint.hi() == "hi" and instanceOf(mkPoint, MkPoint))
## a frozen enum, a module and a class are refused, and what they held is still there
enum MkColor
    RED,
    GREEN
end
var mkRefused = 0
try
    MkColor.clear()
catch e
    mkRefused += 1
end
try
    map.clear(math)
catch e
    mkRefused += 1
end
try
    map.clear(MkPoint)
catch e
    mkRefused += 1
end
assert(mkRefused == 3 and MkColor.RED == 1 and math.sin(0) == 0 and MkPoint().hi() == "hi")
