## Regression tests — Collections: maps, arrays and ranges, the inline cache, equality by identity.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/collections.ol — it must finish without error.

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

## map.len(): the built-in `len` pseudo-method really does receive the map as self (maps do not
## inject self otherwise — a module against a pseudo-method)
var mlen = {a: 1, b: 2, c: 3}
assert(mlen.len() == 3)
mlen["d"] = 4
assert(mlen.len() == 4)
assert({}.len() == 0)
var mlen_def = {len: 42}          ## a defined "len" entry wins over the builtin
assert(mlen_def.len == 42)

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

## typeof distinguishes a built-in module from a plain map, now that Map::kind marks the root
## object of a module (never propagated to whatever the module contains)
assert(typeof(math) == "module")
assert(typeof(map) == "module")
assert(typeof({}) == "map")
assert(typeof(mlm) == "map")

## GET_INDEX inline cache: invalidated when the map mutates, through its version
var ic = {x: 1, y: 2}
var ic_a = ic.x            ## fills the cache: (ic, "x") = 1
ic["x"] = 99               ## a mutation bumps the version, hence invalidates the cache
assert(ic_a == 1)
assert(ic.x == 99)         ## it must read again, not serve 1
ic["x"] = "str"            ## a change of type through the same site
assert(ic.x == "str")
var ic_s = 0               ## a site inside a loop, mutated every turn
for i = 1, 5 do
    ic["x"] = i
    ic_s += ic.x
end
assert(ic_s == 15)

## GET_INDEX inline cache: it only ever covers the object's OWN data. A resolution through the
## chain (__class__, __parent__) is NOT cached, so a mutation of the class stays visible from an
## instance already created.
class ICA
    func init(v)
        self.v = v
    end
    func kind()
        return "ICA"
    end
end
class ICB extends ICA
    func kind()
        return "ICB"
    end
end
var ica = ICA(1)
assert(ica.v == 1)         ## an own field, hence cacheable
ica.v = 2
assert(ica.v == 2)         ## a mutation of the instance bumps the version, so nothing stale
ICA["tag"] = "c1"
assert(ica.tag == "c1")    ## through the chain, which is not cached
ICA["tag"] = "c2"
assert(ica.tag == "c2")    ## a second mutation of the class is seen
ica["tag"] = "own"
assert(ica.tag == "own")   ## the own data shadows the class
var icb = ICB(5)
assert(icb.kind() == "ICB")
assert(icb.get_v_ok == nil)
assert(ICB.tag == "c2")    ## inherited through __parent__

## array pseudo-methods served by array_module, with no chain of strcmp in GET_INDEX: an unknown
## field must stay an ERROR, not nil.
var arr_err = false
try
    var bad_field = [1, 2].zzz
    print(bad_field)
catch e
    arr_err = true
end
assert(arr_err)
## for..in walks a SNAPSHOT of the array (ArrayIterator copies it at MAKE_ITER): a delete during
## the loop does not skip or repeat elements, but the deleted index still shows up on later turns
## since the loop never re-reads the live array.
var snap_seen = []
var snap_arr = [10, 20, 30, 40, 50]
for si, sv in snap_arr do
    snap_seen.push(sv)
    if si == 2 then
        snap_arr.delete(2)
    end
end
assert(snap_seen.join(",") == "10,20,30,40,50")   ## unaffected by the delete
assert(snap_arr.len() == 4)                       ## the live array DID shrink
## …and that snapshot is exactly why arr.delete(i) is NOT safe for "remove every dead one" inside
## the same loop: i is a position in the frozen snapshot, and it drifts past the live array's
## shrinking bounds once more than one element has already been removed.
var drift_arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
var drift_dead = [true, false, true, false, true, false, true, false, true, false, true]
var drift_err = false
try
    for di, dv in drift_arr do
        if drift_dead[di] then
            drift_arr.delete(di)
        end
    end
catch e
    drift_err = true
end
assert(drift_err)      ## "array index out of bounds" once the drift outruns the live array
## arr.remove(v) has no such drift: it looks up v by IDENTITY in the LIVE array (ValueEqual, never
## a script's __eq), wherever it now sits, so removing several objects in the same for..in loop —
## the actual use case a snapshot-based iterator invites — works regardless of how many turns
## already shrank the array.
class RmObj
    func init(n)
        self.n = n
    end
end
var rm_arr = []
for ri = 1, 11 do
    rm_arr.push(RmObj(ri))
end
for ri, ro in rm_arr do
    if ro.n % 2 == 1 then
        assert(rm_arr.remove(ro) == ro)    ## returns the removed object itself
    end
end
assert(rm_arr.len() == 5)
assert(rm_arr[1].n == 2 and rm_arr[5].n == 10)
assert(rm_arr.remove(RmObj(2)) == nil)     ## a DIFFERENT instance with the same field: no identity match
## indexOf and contains share the same identity rule as remove — never a script's __eq — and
## indexOf is 1-based, like every other array index.
var idx_arr = [RmObj(2), RmObj(4), RmObj(6)]
assert(idx_arr.indexOf(idx_arr[2]) == 2)
assert(idx_arr.indexOf(RmObj(4)) == nil)       ## a different instance, same field: no match
assert(idx_arr.contains(idx_arr[3]))
assert(not idx_arr.contains(RmObj(6)))
assert([1, 2, 3].indexOf(2.0) == 2 and [1, 2, 3].contains(2.0))   ## numbers: value equality, INTEGER(2) == FLOAT(2.0)
## sorting: an explicit comparator, and an order by type rank without one
var srt = [1, 2, 3].sort(func(x, y) return x > y end)
assert(srt[1] == 3)
assert(srt[3] == 1)
var srt_mix = [3, "a", nil, 1].sort()
assert(srt_mix[1] == nil)      ## nil < numbers < strings
assert(srt_mix[2] == 1)
assert(srt_mix[4] == "a")
## insert(v) is push, insert(i, v) is positional (1-based)
var ins = [1, 2]
ins.insert(9)
assert(ins[3] == 9)
ins.insert(1, 7)
assert(ins[1] == 7)

## inline cache: the cached value is a NON-owning reference to the slot inside the map. The
## destination register may alias the object's own (`m = m.inner`), and the write would then
## destroy the map the value comes from, so the copy must happen BEFORE the register is written.
var ali = {inner: {v: 42}}
ali = ali.inner
assert(ali.v == 42)
var deep = {x: {x: {x: 9}}}
var pd = deep
for i = 1, 2 do
    pd = pd.x
end
assert(pd.x == 9)

## Writing nil onto a name that collides with a class method or the `len` fallback is a NO-OP
## (nil erases an absent key), so neither resolution can ever be confused by it.
class NilSh
    func init()
        self.a = 1
    end
    func m()
        return "klass"
    end
end
var nsh = NilSh()
nsh["m"] = nil
assert(nsh.m() == "klass")     ## the class method stays reachable
var nlen = {x: 1}
nlen["len"] = nil
assert(nlen.len() == 1)         ## the one REAL key; the built-in `len` fallback still resolves

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

## A native member that calls back into Ollin must not keep a REFERENCE into the register file:
## the call can grow it, which reallocates it. map/filter/reduce/sort held `ctx.args[0]` and
## `ctx.args[1]` by reference, so a callback recursing deep enough made them read freed memory —
## map gave back nil for every element instead of the returned values.
func rq_deep(n)
    if n <= 0 then
        return 0
    end
    return rq_deep(n - 1)
end
var rq_src = [1, 2, 3]
var rq_map = rq_src.map(func(v) rq_deep(300) return v * 10 end)
assert(rq_map[1] == 10)
assert(rq_map[2] == 20)
assert(rq_map[3] == 30)
assert(len(rq_src.filter(func(v) rq_deep(300) return v > 1 end)) == 2)
assert(rq_src.reduce(func(a, v) rq_deep(300) return a + v end, 0) == 6)
var rq_sorted = [3, 1, 2]
rq_sorted.sort(func(a, b) rq_deep(300) return a < b end)
assert(rq_sorted[1] == 1)
assert(rq_sorted[3] == 3)
