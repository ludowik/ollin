## Regression tests — Member access: the inline cache and names that collide with class members.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/access.ol — it must finish without error.

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
