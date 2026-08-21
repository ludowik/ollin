## Regression tests — bugs fixed during the parser and compiler reviews.
## Each block locks down one precise bug (none was caught by syntax.ol).
## Run: ./build/ollin tests/regressions.ol — it must finish without error.

## ── Compiler: multiple returns ──────────────────────────────────────────────
## #1 multiple returns from a CLOSURE (a segfault before: CALL_FUNC without upvals)
var acc = 100
func split() return acc, acc * 2 end
var mr1, mr2 = split()
assert(mr1 == 100)
assert(mr2 == 200)

## #3 multiple returns from a METHOD and from a DYNAMIC CALL (the second value was nil before)
global obj = {}
func obj.two() return 10, 20 end
var me1, me2 = obj.two()
assert(me1 == 10)
assert(me2 == 20)

var dynf = func() return 7, 8 end
var dy1, dy2 = dynf()
assert(dy1 == 7)
assert(dy2 == 8)

## named multiple returns plus a global (no regression)
func pair() return 1, 2 end
var pa1, pa2 = pair()
assert(pa1 == 1 and pa2 == 2)
global gl1, gl2 = pair()
assert(gl1 == 1 and gl2 == 2)

## ── Compiler: register clobbered by a zero-argument call ────────────────────
## #4 object[key] and object.field where the object is a zero-argument call (nil, or a crash, before)
func mkmap() return {x: 42} end
assert(mkmap().x == 42)
func mkarr() return [9, 8] end
assert(mkarr()[1] == 9)

## #5 a zero-argument call as the LEFT operand: its result must not be overwritten by the
## evaluation of the right one
func mk5() return 5 end
func mk3() return 3 end
assert(mk5() + 2 == 7)
assert(mk5() + mk3() == 8)

## #6 switch on a zero-argument call as its subject (the wrong branch was taken before)
func subj() return 2 end
var branch = "none"
switch subj()
    case 1
        branch = "a"
    case 2
        branch = "b"
end
assert(branch == "b")

## ── Compiler: super ─────────────────────────────────────────────────────────
## #2 super across three levels (infinite recursion before: self.__class__.__parent__)
class SA
    func tag() return "A" end
end
class SB extends SA
    func tag() return super.tag() end
end
class SC extends SB
    func tag() return super.tag() end
end
assert(SC().tag() == "A")

## super across two levels, with a value (no regression)
class NA
    func val() return 1 end
end
class NB extends NA
    func val() return super.val() + 10 end
end
assert(NB().val() == 11)

## ── VM: instantiating a class through a map field (the alias.Class() case) ──
class Widget
    func init(v) self.n = v end
end
global ns = {}
ns.W = Widget
var wi = ns.W(7)
assert(wi.n == 7)

## ── Parser: chained and indexed lvalues ────────────────────────────────────
## #7 assignments to a chained target ("unexpected token '='" before)
global cm = {b: {c: 0}}
cm.b.c = 9
assert(cm.b.c == 9)
cm.b.c += 5
assert(cm.b.c == 14)

global cf = {a: [0, 0]}
cf.a[1] = 7
assert(cf.a[1] == 7)

global nn = [[0]]
nn[1][1] = 9
assert(nn[1][1] == 9)

## self.field.sub = ... inside a method
class Holder
    func init() self.p = {x: 0} end
    func setx(v) self.p.x = v end
end
var ho = Holder()
ho.setx(42)
assert(ho.p.x == 42)

## ── Parser: a left-open range at the top level ──────────────────────────────
## #8 ]a;b] at the top level ("';' is not valid syntax" before)
var openr = 0
for i in ]1; 4] do
    openr += i
end
assert(openr == 9)     ## 2 + 3 + 4

## ── VM: try/catch of a runtime error raised by a CALLED function ────────────
## (before: `base` was not restored in the C++ catch, so the catch variable was wrong)
func vm_boom() assert(false, "kaboom") end
global caught = "none"
try
    vm_boom()
catch e
    caught = e
end
assert(caught == "kaboom")

## ── VM: destructuring a SINGLE-VALUE call gives nil ─────────────────────────
## (the regression: a builtin, a constructor or an optional call left stale registers instead
## of nil)
var mrx = [4, 5, 6]
var la, lb = len(mrx)
assert(la == 3)
assert(lb == nil)
class MrPt
    func init(x, y) self.x = x self.y = y end
end
var pa, pb = MrPt(1, 2)
assert(pa.x == 1)
assert(pb == nil)
var mrf = nil
var oa, ob = mrf?()
assert(oa == nil and ob == nil)

## ── VM: <> honours __eq (before: == and <> were true at once) ───────────────
class EqV
    func init(x) self.x = x end
    func __eq(o) return self.x == o.x end
end
assert(EqV(1) == EqV(1))
assert(not (EqV(1) <> EqV(1)))
assert(EqV(1) <> EqV(2))

## ── VM: symmetric comparisons of instances (__lt and __le) ──────────────────
## (before: an instance to the left of > or to the right of < raised an error)
class CmpN
    func init(v) self.v = v end
    func __lt(o) return self.v < o end
    func __le(o) return self.v <= o end
end
var cn = CmpN(5)
assert(cn < 9)
assert(9 > cn)
assert(cn > 3)      ## an instance on the LEFT of >
assert(3 < cn)      ## an instance on the RIGHT of <
assert(cn >= 5)
assert(cn <= 5)

## ── VM: concatenation with __str, and no use-after-free ─────────────────────
class StrP
    func __str() return "SP" end
end
assert("x=" + StrP() == "x=SP")

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
assert(math.exp(1000) > 1000000000000000000)   ## inf → reste flottant, comparable
assert(math.sqrt(-1) <> math.sqrt(-1))          ## nan is not nan: it stays a float nan
var big_f = 100000000000000000000.5
assert(big_f > 1000000000000000000)             ## ~1e20 stays a float, with no undefined cast

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
var mk_huge = math.pow(2.0, 100)     ## 2^100, float entier >> 2^63
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
    var rng_bad = ]0; math.exp(1000)]          ## range ouvert (MAKE_RANGE), borne +inf
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

## ── a static builtin: the class and instance forms agree (as a Ollin `static func` does) ──
## A builtin declared static does not receive self, so its first parameter sits in R[0] whether
## the call is on the class or on an instance (before, self was injected on an instance, the
## parameter was shifted, and the argument was read wrongly).
var col_a = Color.gray(0.5)              ## a parameterised static factory, on the class
assert(col_a.r == 0.5 and col_a.b == 0.5)
var col_c = Color(1, 0, 0)
var col_b = col_c.gray(0.25)            ## the SAME method, on an instance: the parameter sits in R[0]
assert(col_b.r == 0.25 and col_b.g == 0.25)
assert(Color.random().a == 1 and col_c.random().a == 1)  ## random statique, deux modes

## ── core: printing several instances that have __str (a use-after-free before) ──
## value_to_string(__str) runs bytecode and may reallocate regs; print read args[i] straight from
## regs, which left a dangling pointer for the following arguments. Fixed by copying the
## arguments, as printf does. We merely check that it does not crash.
class PrUAF
    func init(n) self.n = n end
    func __str() return "P" + self.n end
end
func pr_deep(d)
    if d > 0 then
        return pr_deep(d - 1)
    end
    return PrUAF(9)
end
print(PrUAF(1), 42, PrUAF(2), PrUAF(3))
print(pr_deep(30), PrUAF(4), pr_deep(20))

## ── math: int consistency (clamp, pow and logn folded as MATH1 and min/max), plus map and 0 ──
assert(typeof(math.clamp(5, 0, 10)) == "int")   ## avant : float
assert(math.clamp(5, 0, 10) == 5)
assert(typeof(math.pow(2, 3)) == "int" and math.pow(2, 3) == 8)
assert(typeof(math.pow(2, 0.5)) == "float")     ## a non-integer stays a float
assert(typeof(math.logn(8, 2)) == "int" and math.logn(8, 2) == 3)
assert(math.map(5, 2, 2, 7, 99) == 7)           ## a zero input range gives out_lo, and no inf or nan
assert(not math.isInf(math.map(5, 2, 2, 0, 10)))
assert(math.map(5, 0, 10, 0, 100) == 50)

## ── string and math: the double-to-int cast is guarded (undefined behaviour, and a WASM trap, on a huge index before) ──
assert(string.char("abc", 1e300) == "")         ## an index out of range gives "", and does not trap
assert(string.char("abc", math.sqrt(-1)) == "") ## NaN
assert(string.substr("hello", 1e300) == "")
assert(string.substr("hello", 2, 1e300) == "ello")  ## a huge len is clamped
assert(string.char("abc", 2) == "b")            ## cas normal
global str_c = "none"
try
    var r = math.randInt(1e300)                ## arg hors plage int64 → erreur claire
catch e
    str_c = "x"
end
assert(str_c == "x")

## ── string: indexing by CHARACTER (a UTF-8 codepoint), not by byte ─────────
assert(len("café") == 4)                     ## four characters (é takes two bytes)
assert(len("héllo") == 5)
assert(len("a€b") == 3)                       ## € takes three bytes, and is one character
assert(string.char("café", 4) == "é")        ## before: a fragment of a byte
assert(string.char("a€b", 2) == "€")
assert(string.substr("café", 1, 3) == "caf")
assert(string.substr("café", 4, 1) == "é")
assert(string.substr("héllo", 2, 2) == "él")
assert(len("hello") == 5)                     ## ASCII unchanged
assert(string.char("café", 9) == "")         ## out of bounds gives ""
## upper and lower: ASCII plus accented Latin-1; trim works by codepoint
assert(string.upper("café") == "CAFÉ")
assert(string.lower("ÉÀÙÇ") == "éàùç")
assert(string.upper("straße") == "STRASSE")  ## ß → SS
assert(string.trim("··café··", "·") == "café")  ## trim works by codepoint (· takes two bytes)
assert(string.rtrim("«café»", "»") == "«café")
## string.len: a length in codepoints, on strings only, unlike the polymorphic global len
assert(string.len("café") == 4)               ## é takes two bytes, and is one character
assert(string.len("a€b") == 3)                ## € takes three bytes, and is one character
assert(string.len("") == 0)
assert(string.len("hello") == len("hello"))   ## consistent with the global len on a string
global str_len_err = "none"
try
    string.len([1, 2, 3])                     ## a non-string is an error, unlike the global len
catch e
    str_len_err = "caught"
end
assert(str_len_err == "caught")

## a nested if in first position of an else branch (there is no "else if" sugar, only elseif)
var ei = "?"
if false then
    ei = "then"
else
    if true then
        ei = "else>if"
    end
end
assert(ei == "else>if")
## elseif stays distinct, and works
var ec = 0
if false then
    ec = 1
elseif true then
    ec = 2
else
    ec = 3
end
assert(ec == 2)

## mem(): the heap memory in use, in bytes, as an integer — it grows with the allocations
assert(typeof(mem()) == "int")
assert(mem() > 0)
var mem_before = mem()
var big = []
for i = 1, 20000 do
    big[i] = i
end
assert(mem() >= mem_before)     ## allocating a big array did not lower the memory

## ── Compiler: the lexical scope of `var` starts at its declaration ─────────
## The bug: a `var` declared further down shadowed an earlier reference, which then read an
## uninitialised register (nil at the top level, a leftover value inside a function). Now, above
## its line the name resolves to the global, and the local only shadows from the `var` on.
global lex_g = 2
assert(lex_g == 2)          ## a reference BEFORE the `var lex_g` below, hence the global
var lex_g = 1               ## from here on: the local
assert(lex_g == 1)

## `var x = x`: the initialiser reads the OUTER x, not the local being declared
global lex_h = 7
func lex_init()
    var lex_h = lex_h + 1   ## RHS = global (7) → locale = 8
    return lex_h
end
assert(lex_init() == 8)
assert(lex_h == 7)          ## the global unchanged

## a `do` block: the same rule, in its own compartment
global lex_b = 3
do
    assert(lex_b == 3)      ## before the block's var, hence the global
    var lex_b = 9
    assert(lex_b == 9)
end
assert(lex_b == 3)          ## outside the block, the global again

## ── Compiler: expanding `...`, and spreading a call in last position ───────
## `...` and a call in LAST position expand to ALL of their values, as in Lua. Before, `...` gave
## a single value — or garbage when empty — outside a `return`.
func va_sum(...)
    var s = 0
    for v in [...] do s += v end   ## [...] is every vararg
    return s
end
assert(va_sum() == 0)
assert(va_sum(1, 2, 3, 4) == 10)

## forwarding: f(head, ...) passes on every vararg, with a dynamic argc
func va_fwd(head, ...) return head + va_sum(...) end
assert(va_fwd(100, 1, 2, 3) == 106)

## using the varargs several times in one body, with no corruption after a spread
func va_twice(...)
    var a = va_sum(...)
    var b = va_sum(...)
    return a + b
end
assert(va_twice(1, 2, 3) == 12)

## ... as a single value: the first vararg, or nil when there is none (no more garbage)
func va_first(...) return ... end
var vf = va_first(9, 8)
assert(vf == 9)

## multiple assignment from ...: var a, b = ...
func va_take2(...)
    var a, b = ...
    return a, b
end
var vt1, vt2 = va_take2(11, 22, 33)
assert(vt1 == 11 and vt2 == 22)
var vu1, vu2 = va_take2(5)
assert(vu1 == 5 and vu2 == nil)

## spreading a call in last position: f(a, g()), return g(), [x, g()]
func va_pair() return 1, 2 end
func va_add3(a, b, c) return a + b + c end
assert(va_add3(10, va_pair()) == 13)        ## g() expanded as the last argument
func va_ret() return va_pair() end
var vr1, vr2 = va_ret()
assert(vr1 == 1 and vr2 == 2)               ## returning a call in last position, expanded
var va_a = [0, va_pair()]
assert(len(va_a) == 3 and va_a[2] == 1 and va_a[3] == 2)  ## [x, g()] expanded

## a call in a NON-final position is adjusted to one value, as in Lua
func va_one(x) return x end
assert(va_one(va_pair()) == 1)

## ── Compiler: lexical shadowing block by block ─────────────────────────────
## A `var` in a nested block shadows the outer local, in a register of its own, and the outer one
## is intact after the block. This regressed for a while through bind_scan_locals, which reused
## the outer register whenever the name was already bound, in an inherited scope.
var shadow_x = 1
do
    var shadow_x = 99
    assert(shadow_x == 99)
end
assert(shadow_x == 1)
## the initialiser reads the scope before the declaration (var z = the outer z)
func shadow_outer()
    var z = 3
    do
        var z = z + 100   ## RHS = z externe (3)
        assert(z == 103)
    end
    return z              ## externe intacte
end
assert(shadow_outer() == 3)

## ── Formatting {expr:spec} in an interpolation and {N:spec} in printf, sharing one engine ──
## The spec's ':' is the one at the TOP level: a nested map literal preserves it.
var fmt_v = 3.14159
assert("{fmt_v:.2f}" == "3.14")
assert("{fmt_v:8.3f}" == "   3.142")           ## width and precision
assert("{(255):x}" == "ff")                     ## hex, on a parenthesised expression
assert("{(255):#06x}" == "0x00ff")             ## the # flag, zero padding and a width
assert("{(-7):+d}" == "-7")                     ## a forced sign
assert("{(42):d}" == "42")
assert("{(3.9):d}" == "3")                       ## coercition float→int (troncature)
assert("{"hi":5s}" == "   hi")                 ## width 5, right-aligned, as C defaults to
assert("{"hi":-5s}" == "hi   ")                ## '-' means left-aligned, the C printf syntax, not '>'
## the ':' of a nested map is NOT a spec separator
var fmt_m = {"a": 1}
assert("{fmt_m["a"]}" == "1")
assert("{ {"k": 7}.k }" == "7")
## {N} and {} are positional placeholders, hence LITERALS outside printf
assert("{1}-{2}" == "{1}-{2}")
assert("{}" == "{}")                             ## no more "empty interpolation" error
## an invalid spec gives a clear runtime error
var fmt_err = false
try
    var bad = "{fmt_v:.2z}"
    print(bad)
catch e
    fmt_err = true
end
assert(fmt_err)

## map.len(): the built-in `len` pseudo-method really does receive the map as self (maps do not
## inject self otherwise — a module against a pseudo-method)
var mlen = {a: 1, b: 2, c: 3}
assert(mlen.len() == 3)
mlen["d"] = 4
assert(mlen.len() == 4)
assert({}.len() == 0)
var mlen_def = {len: 42}          ## a defined "len" entry wins over the builtin
assert(mlen_def.len == 42)

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
assert(ica.v == 1)         ## champ propre → cacheable
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

## `nil` means ABSENT in a map: an own key holding nil does NOT shadow what the prototype chain —
## or the `len` fallback — would provide. A regression becomes possible when moving from a lookup
## by value to a lookup by key presence.
class NilSh
    func init()
        self.a = 1
    end
    func m()
        return "classe"
    end
end
var nsh = NilSh()
nsh["m"] = nil
assert(nsh.m() == "classe")     ## the class method stays reachable
var nlen = {}
nlen["len"] = nil
assert(nlen.len() == 1)         ## the built-in `len` fallback; the map has one key

## ── enum ────────────────────────────────────────────────────────────────────
## Numbering: 1 by default, then +1 each time; an integer literal redefines what follows; a
## non-literal value — here a string — leaves the counter where it is.
enum RgEtat REPOS = 0, MARCHE, SAUT = 10, CHUTE end
assert(RgEtat.REPOS == 0 and RgEtat.MARCHE == 1)
assert(RgEtat.SAUT == 10 and RgEtat.CHUTE == 11)
enum RgMix A, B = "texte", C end
assert(RgMix.A == 1 and RgMix.B == "texte" and RgMix.C == 2)
enum RgNeg X = -3, Y end
assert(RgNeg.X == -3 and RgNeg.Y == -2)
enum RgAlias UN = 1, FIRST = 1 end       ## a repeated value is an alias, and is allowed
assert(RgAlias.UN == RgAlias.FIRST)

## For READING, an enum is an ordinary map: len, iteration, and values of any type.
enum RgCol ROUGE, VERT, BLEU end
assert(#RgCol == 3)
var rg_sum = 0
for k, v in RgCol do
    rg_sum = rg_sum + v
end
assert(rg_sum == 6)
func rg_carre(x) return x * x end
enum RgObj L = [1, 2, 3], F = rg_carre end
assert(RgObj.L[2] == 2 and RgObj.F(5) == 25)

## The freeze is SHALLOW: the enum refuses a write, the object it holds does not.
RgObj.L[1] = 99
assert(RgObj.L[1] == 99)

## The lock at run time: an alias and a computed key both go through the same SET_INDEX.
var rg_alias = RgCol
var rg_caught = 0
try
    rg_alias.ROUGE = 9
catch e
    rg_caught = rg_caught + 1
end
try
    var rg_k = "VERT"
    rg_alias[rg_k] = 9
catch e
    rg_caught = rg_caught + 1
end
assert(rg_caught == 2 and RgCol.ROUGE == 1 and RgCol.VERT == 2)

## an enum into an existing map, the `a.b` form.
global rgCfg = {}
enum rgCfg.mode PLEIN, FENETRE end
assert(rgCfg.mode.PLEIN == 1 and rgCfg.mode.FENETRE == 2)

## Pool recycling: the enum marking must not contaminate a reused map. The maps below are freed,
## then their memory is handed out again.
for i = 1, 200 do
    var rg_tmp = {a: i}
    rg_tmp.a = i + 1
    assert(rg_tmp.a == i + 1)
end
var rg_libre = {}
rg_libre.x = 1
assert(rg_libre.x == 1)


## Exporting a module: every kind of declaration must end up in the map `import ... as` creates.
## An enum was missing from it — collect_top_level_names knew nothing of EnumDeclStmt — so
## m.MyEnum was nil.
import "exports_test" as expMod
assert(expMod.expVar == 1)
assert(expMod.expGlobal == 2)
assert(expMod.expFunc() == 3)
assert(ExpClass().v == 4)          ## the class is exported, and can be instantiated through the name
assert(expMod.ExpClass <> nil)
assert(expMod.ExpEnum.A == 1 and expMod.ExpEnum.B == 2)
assert(expMod.dansUneMap == nil)   ## `enum a.b` exports no name of its own


## Pre-scanning the globals: a `global` declared at the BOTTOM of every kind of construct must be
## seen before compilation. The functions below read it although they are declared BEFORE the
## global's declaration: if the walk does not descend into a construct, compilation fails on
## "undeclared variable". (This locks down Stmt::for_each_body: a statement with a body left out
## breaks here.)
func psLire() return psWhile + psIf + psElseIf + psElse + psFor + psFunc + psDo end
func psLire2() return psSwitch + psSwitchElse + psTry + psCatch + psTryElse + psMethode end

while true do
    global psWhile = 1
    break
end
if true then
    global psIf = 2
elseif false then
    global psElseIf = 3
else
    global psElse = 4
end
if false then
    psElseIf = 3
end
psElseIf = 3
psElse = 4
for i = 1, 1 do
    global psFor = 5
end
func psPorteuse()
    global psFunc = 6
end
psPorteuse()
do
    global psDo = 7
end
switch 1
    case 1 do
        global psSwitch = 8
    end
    else
        global psSwitchElse = 9
end
psSwitchElse = 9
try
    global psTry = 10
    throw "x"
catch e
    global psCatch = 11
end
try
    var psRien = 0
catch e
else
    global psTryElse = 12   ## the try's `else` block: it runs when nothing was thrown
end
class PsClasse
    func m()
        global psMethode = 13
        return psMethode
    end
end
PsClasse().m()

assert(psLire() == 1 + 2 + 3 + 4 + 5 + 6 + 7)
assert(psLire2() == 8 + 9 + 10 + 11 + 12 + 13)


## A closure capturing the loop variable from a NESTED block. body_has_func decides whether the
## loop closes its upvalues and keeps its registers reserved; it had no case for `do ... end` — an
## inherited no-op — and answered "no function here", so the registers were recycled and the
## closure read a reused one: dfDo[1]() returned {function} instead of a number. Each iteration
## has a variable of its own.
var dfDo = []
for i = 1, 3 do
    do
        dfDo[#dfDo + 1] = func() return i end
    end
end
assert(dfDo[1]() == 1 and dfDo[2]() == 2 and dfDo[3]() == 3)

var dfIf = []
for i = 1, 3 do
    if true then
        dfIf[#dfIf + 1] = func() return i end
    end
end
assert(dfIf[1]() == 1 and dfIf[3]() == 3)

var dfSw = []
for i = 1, 3 do
    switch 1
        case 1 do
            dfSw[#dfSw + 1] = func() return i end
        end
    end
end
assert(dfSw[1]() == 1 and dfSw[3]() == 3)

var dfTry = []
for i = 1, 3 do
    try
        dfTry[#dfTry + 1] = func() return i end
    catch e
    end
end
assert(dfTry[1]() == 1 and dfTry[3]() == 3)


## A closure capturing a LOCAL OF THE LOOP BODY, called AFTER the loop. compile_block reserves
## the registers of the body's locals when the body contains a function; both loops then
## overwrote reg_top_ with the loop variables' reservation alone, which is lower, so the local's
## register became a temporary again and the next call overwrote the value under an upvalue still
## open (one read {function} instead of the value).
var clNum = []
for i = 1, 3 do
    var copy = i * 10
    clNum[#clNum + 1] = func() return copy end
end
assert(clNum[1]() == 10 and clNum[2]() == 20 and clNum[3]() == 30)

var clIter = []
for v in ["a", "b", "c"] do
    var copy = v
    clIter[#clIter + 1] = func() return copy end
end
assert(clIter[1]() == "a" and clIter[2]() == "b" and clIter[3]() == "c")

var clPair = []
for k, v in {x: 1} do
    var copy = k + "=" + v
    clPair[#clPair + 1] = func() return copy end
end
assert(clPair[1]() == "x=1")


## Closing the upvalues at the end of an iteration (CLOSE_UPVALS): every exit and every loop-back
## path must go through it, and two closures of the same turn must go on SHARING their variable
## (one upvalue per register and per turn).
var upBreak = []
for i = 1, 5 do
    upBreak[#upBreak + 1] = func() return i end
    if i == 3 then break end
end
assert(#upBreak == 3 and upBreak[1]() == 1 and upBreak[3]() == 3)

var upCont = []
for i = 1, 4 do
    if i % 2 == 0 then continue end
    upCont[#upCont + 1] = func() return i end
end
assert(#upCont == 2 and upCont[1]() == 1 and upCont[2]() == 3)

var upPart = []
for i = 1, 2 do
    var n = i * 10
    upPart[#upPart + 1] = [func() return n end, func() n = n + 1 end]
end
var upP1 = upPart[1]
upP1[2]()                       ## writes into the variable of the FIRST turn
var upP2 = upPart[2]
assert(upP1[1]() == 11 and upP2[1]() == 20)

var upNest = []
for i = 1, 2 do
    for j = 1, 2 do
        upNest[#upNest + 1] = func() return i * 10 + j end
    end
end
assert(upNest[1]() == 11 and upNest[2]() == 12 and upNest[3]() == 21 and upNest[4]() == 22)

func upReturn()
    for i = 1, 3 do
        var f = func() return i end
        if i == 2 then
            return f
        end
    end
end
assert(upReturn()() == 2)


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
var rfEchappe = nil
do
    var rfInterne = "dedans"
    rfEchappe = ref rfInterne
end
assert(rfEchappe.get() == "dedans")


## ── The tween module ───────────────────────────────────────────────────────
## Advancing by EXACT steps (0.25 × 4): a step of 0.1 accumulated ten times does not quite make
## one second in binary, and the tween would not be finished.
tween.cancelAll()
var twObj = {x: 0, n: 0, teinte: Color(0, 0, 0)}
var twT = tween.to(twObj, {x: 8}, 1.0, "linear")
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 4 and twT.progress() == 0.5)
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 8 and twT.isDone() and tween.count() == 0)

## A step longer than the time left stops at the target, with no overshoot.
tween.to(twObj, {x: 5}, 0.5, "linear")
tween.update(10.0)
assert(twObj.x == 5)

## With BOTH the start and the target integers, the value stays an integer throughout, with no float drift.
tween.to(twObj, {n: 10}, 1.0, "linear")
tween.update(0.5)
assert(twObj.n == 5 and typeof(twObj.n) == "int")

## An overshooting curve: the final value must be the EXACT target, not 0.99.
var twFini = false
tween.to(twObj, {x: 20}, 0.5, "easeOutBack", func() twFini = true end)
tween.update(0.5)
assert(twObj.x == 20 and twFini)

## Structural interpolation: a class instance animates field by field.
tween.to(twObj, {teinte: Color(1, 0.5, 0)}, 1.0, "linear")
tween.update(1.0)
assert(twObj.teinte.r == 1 and twObj.teinte.g == 0.5 and twObj.teinte.b == 0)

## A plain variable by reference, and a curve given as a FUNCTION.
var twVal = 0
tween.value(ref twVal, 100, 1.0, func(p) return p * p end)
tween.update(0.5)
assert(twVal == 25)
tween.update(0.5)
assert(twVal == 100)

## Two tweens on the SAME field: the second cancels the first, which would otherwise fight it and
## make the result depend on the iteration order.
twObj.x = 0
tween.to(twObj, {x: 50}, 1.0, "linear")
tween.to(twObj, {x: -50}, 1.0, "linear")
assert(tween.count() == 1)
tween.update(1.0)
assert(twObj.x == -50)

## Delay: nothing moves before it elapses, and the starting value is the one read AT THE START.
twObj.x = 0
tween.to(twObj, {x: 10}, 1.0, "linear").delay(0.5)
tween.update(0.4)
assert(twObj.x == 0)
twObj.x = 100          ## written during the delay, and that is where the animation starts from
tween.update(0.6)      ## 0.1 s of delay left, then 0.5 s of animation
assert(twObj.x == 55)

## Pause and resume.
twObj.x = 0
var twP = tween.to(twObj, {x: 10}, 1.0, "linear")
tween.update(0.5)
twP.pause()
tween.update(0.5)
assert(twObj.x == 5)
twP.resume()
tween.update(0.5)
assert(twObj.x == 10)

## A completion callback that DECLARES a tween: it push_backs onto the table during the advancing
## pass, so any reference kept across the call would dangle.
var twChain = 0
tween.to(twObj, {x: 0}, 0.5, "linear", func()
    twChain = 1
    tween.to(twObj, {x: 7}, 0.5, "linear", func() twChain = 2 end)
end)
tween.update(0.5)
assert(twChain == 1)
tween.update(0.5)
assert(twChain == 2 and twObj.x == 7)

## A completion callback that CANCELS everything: the pass must not carry on over dead slots.
tween.to(twObj, {x: 1}, 0.5, "linear", func() tween.cancelAll() end)
tween.to(twObj, {n: 1}, 0.5, "linear")
tween.update(0.5)
assert(tween.count() == 0)

## A CURVE supplied by the script may declare further tweens: the table reallocates in the middle
## of the advancing pass, so nothing may hold a reference to an element.
tween.cancelAll()
var twR = {x: 0, y: 0}
var twN = 0
tween.to(twR, {x: 100}, 1.0, func(p)
    twN += 1
    if twN == 1 then
        tween.to(twR, {y: 50}, 1.0, "linear")
    end
    return p
end)
tween.update(0.5)
tween.update(0.5)
## y = 25: the tween born during the first pass is NOT advanced in it — it would consume a time
## step earlier than its birth — so it only gets the second, and the value no longer depends on
## the slot it was given.
assert(twR.x == 100 and twR.y == 25)

## ── ui.list ────────────────────────────────────────────────────────────────
## With no graphics area, the declaration validates its arguments and initialises the selection:
## that is the part tested here, the rendering and the click needing a display. An array returns a
## VALUE, a map or an enum a KEY — as `for … in` does.
enum LiDiff
    facile,
    normal,
    difficile
end
var liTints = ["rouge", "vert", "bleu"]
var liReglages = {volume: 0.8, brillance: 0.5, alpha: 1}
var liC = nil
var liD = nil
var liR = nil
ui.list("Couleur", liTints, ref liC)
ui.list("Difficulté", LiDiff, ref liD)
ui.list("Réglage", liReglages, ref liR)
assert(liC == "rouge")           ## the array's first element, its VALUE
assert(liD == "facile")          ## an enum sorted by value, hence in declaration order
assert(liR == "alpha")           ## a map sorted by label, hence the first in alphabetical order

## A selection already set is honoured: the initialisation only applies to nil.
var liGarde = "bleu"
ui.list("Couleur", liTints, ref liGarde)
assert(liGarde == "bleu")

## The handle of a finished tween can be queried without error: keeping the handle is normal.
assert(twT.isDone() and twT.progress() == 1)
twT.cancel()

## Multiple reassignment, with no `var`, from a multi-return call: the same value had to reach the
## same target as at declaration. The compiler counted ONE value only, and the following targets
## read neighbouring registers, hence shifted values (1, 1, 2).
func maTrois()
    return 1, 2, 3
end
func maUne()
    return 7
end
global maG1 = 0
global maG2 = 0
var maA, maB, maC = maTrois()
maA, maB, maC = maTrois()
assert(maA == 1 and maB == 2 and maC == 3)
maG1, maG2 = maTrois()
assert(maG1 == 1 and maG2 == 2)
## Fewer values than targets: the targets beyond become nil, not the leftovers of a register.
var maX = 5
var maY = 5
maX, maY = maUne()
assert(maX == 7 and maY == nil)
## Targets that are not plain variables.
var maM = {}
maM.u, maM.v = maTrois()
assert(maM.u == 1 and maM.v == 2)
var maT = [0, 0, 0]
maT[1], maT[3] = maTrois()
assert(maT[1] == 1 and maT[2] == 0 and maT[3] == 2)
## A swap: two values for two targets stays a parallel case, not a multi-return.
var maP = 1
var maQ = 2
maP, maQ = maQ, maP
assert(maP == 2 and maQ == 1)
## A method and varargs take the same path as a named function.
class MyPair
    func deux()
        return 8, 9
    end
end
var myObj = MyPair()
var maD1 = 0
var maD2 = 0
maD1, maD2 = myObj.deux()
assert(maD1 == 8 and maD2 == 9)
func maVarargs(...)
    var maV1, maV2 = ...
    maV1, maV2 = ...
    assert(maV1 == "a" and maV2 == "b")
end
maVarargs("a", "b")

## ── Compiler: the semantics of the loop variable ───────────────────────────
## Three rules an optimisation has already broken: the aliasing of the counter, the variable's
## scope, and the closing of the upvalues at the end of a turn.

## Changing the loop variable inside the body does not affect the iteration: the counter is
## isolated from the visible variable, on the path without aliasing.
var boS = 0
var boN = 0
for i = 1, 3 do
    boS += i
    i = i + 100
    boN += 1
end
assert(boS == 6 and boN == 3)

## The loop variable is local to the loop: an outer variable of the same name is shadowed during
## it, then restored.
var boExt = 99
for boExt = 1, 3 do end
assert(boExt == 99)

## One variable PER ITERATION: the upvalues are closed at the end of a turn, so each closure
## keeps the value of its own turn (the Lua 5.4 and `let` model).
var boCl = []
var boI = 0
for v in [10, 20, 30] do
    boI += 1
    boCl[boI] = func() return v end
end
assert(boCl[1]() == 10 and boCl[2]() == 20 and boCl[3]() == 30)

## ── tween: the reading plan (repeat) ───────────────────────────────────────
## `repeat([count] [, roundTrip])`: with no count the repetition is endless; the second parameter
## adds the return trip of the WHOLE. The positions are read every half-second, the animation
## lasting one second, so we read the middle then the end of each pass. In the headless native
## build it is `tween.update` that advances things, the engine not running.
func plWalk(mods, turns)
    var o = {x: 0}
    var t = tween.to(o, {x: 10}, 1.0, "linear")
    mods(t)
    var vues = []
    for i = 1, turns do
        tween.update(0.5)
        vues[#vues + 1] = math.round(o.x)
    end
    return vues
end

## repeat(2): two forward passes. At the end of the first, the position returns to the start.
var plR = plWalk(func(t) t.repeat(2) end, 5)
assert(plR[1] == 5 and plR[2] == 0 and plR[3] == 5 and plR[4] == 10 and plR[5] == 10)

## repeat(2, true): both forward passes, THEN both return ones (+1 +1 -1 -1). Between two return
## passes the position jumps from 0 to 10, just as it jumps from 10 to 0 between two forward ones:
## each segment replays the whole pass in its own direction.
var plRY = plWalk(func(t) t.repeat(2, true) end, 9)
assert(plRY[4] == 10 and plRY[5] == 5 and plRY[6] == 10 and plRY[8] == 0)

## Two calls COMPOSE: the second acts on the plan already built. repeat(nil, true) then repeat(2)
## gives two round trips (+1 -1 +1 -1).
var plYR = plWalk(func(t) t.repeat(nil, true).repeat(2) end, 9)
assert(plYR[2] == 10 and plYR[4] == 0 and plYR[6] == 10 and plYR[8] == 0)

## The bounds are frozen at the first start: writing into the object mid-animation does not
## redefine the start of the next pass, which would otherwise make a return trip drift.
var plO = {x: 0}
var plT = tween.to(plO, {x: 10}, 1.0, "linear").repeat(2)
tween.update(0.5)
plO.x = 100
tween.update(0.5)
assert(plO.x == 0)
plT.cancel()

## `repeat()` with no count is endless. The tween never finishes on its own, and its progress is
## that of the current turn; the `progress` of a finite plan, on the other hand, covers ALL of its
## segments.
var plL = {x: 0}
var plTL = tween.to(plL, {x: 10}, 1.0, "linear").repeat()
tween.update(2.25)
assert(not plTL.isDone() and math.abs(plTL.progress() - 0.25) < 0.001)
plTL.cancel()
var plF = {x: 0}
var plTF = tween.to(plF, {x: 10}, 1.0, "linear").repeat(4)
tween.update(2.0)
assert(math.abs(plTF.progress() - 0.5) < 0.001)
plTF.cancel()

## A stale handle: keeping the handle of a finished animation is normal, so the modifiers must be
## harmless on it.
var plD = {x: 0}
var plTD = tween.to(plD, {x: 1}, 0.1, "linear")
tween.update(0.2)
assert(plTD.isDone())
plTD.repeat(3)
plTD.repeat(nil, true)
plTD.repeat(2, true)
assert(plTD.isDone())

## ── Booleans: a sealed type, but "empty is false" is kept ──────────────────
## Equality must test BOTH sides of the pair: testing only one would have let `true == 1` answer
## true through the numeric branch, and `false == false` answer FALSE by falling into the default
## case — which really did happen during the implementation.
assert((false == false) == true)
assert((true == true) == true)
assert((true == false) == false)
assert(true <> 1 and 1 <> true)
assert(false <> 0 and 0 <> false)
assert(false <> nil and false <> "" and false <> [])

## The type has a NAME: `typeof` had kept its "unknown" default when the boolean became a type of
## its own, so a script could not recognise it.
assert(typeof(true) == "bool" and typeof(false) == "bool")
assert(typeof(1 < 2) == "bool" and typeof(not nil) == "bool")

## A boolean is a KEY distinct from the matching integer: the hash must separate what equality
## separates, or the two keys would merge inside the map.
var bk = {}
bk[true] = "b"
bk[1] = "i"
bk[false] = "bf"
bk[0] = "z"
assert(bk[true] == "b" and bk[1] == "i" and bk[false] == "bf" and bk[0] == "z")
assert(len(bk) == 4)

## What produces booleans: `not`, the six comparisons, and the native predicates.
assert((not nil) == true)
assert((3 > 4) == false)
assert(("a" < "b") == true)
assert(math.isNan(math.sqrt(-1)) == true)
assert(math.isInf(math.INF) == true)
assert(math.isNan(1.0) == false)

## Display: "true" and "false", in English like the keywords, hence copyable straight into a
## script. The same holds for concatenation and interpolation.
assert(("" + true) == "true")
assert(("" + false) == "false")
var bi = 1 == 1
assert("{bi}" == "true")

## A boolean crosses every boundary unaltered: passed as an argument, returned from a function,
## stored in a map or an array, captured by a closure.
func bool_id(v)  return v  end
assert(bool_id(true) == true and bool_id(false) == false)
var bm = {ok: false}
bm.ok = 1 == 1
assert(bm.ok == true)
var ba = [true, false]
assert(ba[1] == true and ba[2] == false)
var bcap = false
func bool_set()  bcap = 2 > 1  end
bool_set()
assert(bcap == true)

## A boolean stays a valid truth test wherever a value is expected.
var bcount = 0
for i = 1, 3 do
    if i > 1 then bcount += 1 end
end
assert(bcount == 2)
while false do
    assert(nil)   ## jamais atteint
end

## ── data: a boolean survives persistence ───────────────────────────────────
## The regression: `encode_value` knew only integers, floats and strings, so `data.set(k, true)`
## failed as soon as `true` stopped being the integer 1 — and failed with a message that promised
## booleans. The module had no behaviour test at all.
data.set("bt", true)
data.set("bf", false)
data.set("bn", 42)
data.set("bs", "x")
assert(data.get("bt") == true)
assert(data.get("bf") == false)
assert(data.get("bn") == 42 and data.get("bs") == "x")
assert(data.has("bt") and not data.has("jamais_ecrit"))

## The type survives the encoding: what comes back is a BOOLEAN, not the integer 1.
assert(data.get("bt") <> 1)
assert(data.get("bf") <> 0)

## The default value of a missing key, and deletion through nil.
assert(data.get("jamais_ecrit", "defaut") == "defaut")
data.set("bt", nil)
assert(not data.has("bt"))
data.set("bf", nil)
data.set("bn", nil)
data.set("bs", nil)

## ── tween.sequence: a run of steps ─────────────────────────────────────────
## The time key is `delay` in both roles: a duration when the step carries `to`, a wait
## otherwise.
var sqO = {x: 0, y: 0}
var sqT = tween.sequence(sqO, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {delay: 0.5},
    {to: {y: 20}, delay: 1.0, curve: "linear"},
])
tween.update(0.5)
assert(sqO.x == 5 and sqO.y == 0)
tween.update(0.5)
assert(sqO.x == 10)
tween.update(0.5)              ## the wait moves nothing
assert(sqO.x == 10 and sqO.y == 0)
tween.update(1.0)
assert(sqO.y == 20 and sqT.isDone())

## A step's starting value is the one the previous step left, not the one the field held when the
## sequence was declared.
var sqE = {v: 0}
tween.sequence(sqE, [
    {to: {v: 100}, delay: 1.0, curve: "linear"},
    {to: {v: 150}, delay: 1.0, curve: "linear"},
])
tween.update(1.0)
tween.update(0.5)
assert(sqE.v == 125)
tween.cancelAll()

## A step can switch object through `target`.
var sqA = {x: 0}
var sqB = {x: 0}
tween.sequence(sqA, [
    {to: {x: 4}, delay: 1.0, curve: "linear"},
    {target: sqB, to: {x: 8}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(sqA.x == 4 and sqB.x == 8)

## `progress` runs over the whole sequence, in TIME: counting the steps crossed would make the
## progress jump, the durations being unequal.
var sqP = {v: 0}
var sqPT = tween.sequence(sqP, [
    {to: {v: 1}, delay: 3.0, curve: "linear"},
    {to: {v: 2}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(math.abs(sqPT.progress() - 0.5) < 0.001)
sqPT.cancel()

## `repeat` bears on the WHOLE sequence, and the round trip replays it backwards, each step
## reversed. The regression: a time step larger than one step crossed it without reading its
## bounds, and the return trip then set off from a wrong value.
var sqR = {x: 0}
tween.sequence(sqR, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {to: {x: 30}, delay: 1.0, curve: "linear"},
]).repeat(nil, true)
tween.update(2.0)              ## a single step for the whole forward pass
assert(sqR.x == 30)
tween.update(0.5)
assert(sqR.x == 20)            ## the return trip: step 2 replayed from 30 to 10
tween.update(0.5)
assert(sqR.x == 10)
tween.update(1.0)
assert(sqR.x == 0)             ## then step 1, from 10 to 0
tween.cancelAll()

## A wait on its own is a valid sequence, and it does finish.
var sqW = {v: 5}
var sqWT = tween.sequence(sqW, [{delay: 0.5}])
tween.update(0.3)
assert(sqW.v == 5 and not sqWT.isDone())
tween.update(0.3)
assert(sqWT.isDone())

## Overwriting: a tween aiming at the same field cancels the sequence, as it does for tween.to.
var sqX = {x: 0}
tween.sequence(sqX, [{to: {x: 100}, delay: 1.0, curve: "linear"}])
tween.to(sqX, {x: 50}, 1.0, "linear")
tween.update(1.0)
assert(sqX.x == 50 and tween.count() == 0)

## ── The sound module: oscillators ──────────────────────────────────────────
## With no device the whole API still answers: the voices exist, and their parameters can be read
## and written. Only the output is mute, which makes the synthesis testable in a container with no
## sound card.
var osA = sound.sine(440)
assert(osA.freq() == 440 and osA.shape() == "sine")
assert(osA.volume() == 0.5 and osA.pan() == 0)
assert(not osA.isPlaying())

## Writes return the HANDLE, hence they chain; reads return the value.
assert(osA.freq(880).volume(0.25).pan(-1) == osA)
assert(osA.freq() == 880 and osA.volume() == 0.25 and osA.pan() == -1)

## start and stop toggle the state, and chain too.
osA.start()
assert(osA.isPlaying())
osA.stop()
assert(not osA.isPlaying())

## Volume and pan are CLAMPED silently, like the master volume.
assert(osA.volume(5) == osA and osA.volume() == 1)
assert(osA.pan(-9) == osA and osA.pan() == -1)
assert(osA.pan(9) == osA and osA.pan() == 1)

## Each shorthand sets its waveform, and `shape` reads it back by name.
assert(sound.square(100).shape() == "square")
assert(sound.saw(100).shape() == "saw")
assert(sound.triangle(100).shape() == "triangle")
assert(sound.noise().shape() == "noise")
assert(sound.osc(220, "square").shape() == "square")

## The shape can be changed while running, as the frequency can.
assert(osA.shape("saw").shape() == "saw")

## Recycling: when the table is full, the OLDEST stopped voice is taken back — by creation rank,
## not the first slot that comes, which kept hammering the same one. The handle taken back is
## detected as stale instead of naming the next caller's voice.
var osVieux = sound.sine(200)
var osNeuf = nil
for i = 1, 20 do
    osNeuf = sound.sine(300)
end
var osPerime = false
try
    osVieux.freq()
catch e
    osPerime = true
end
assert(osPerime and osNeuf.freq() == 300)

## The envelope is carried by the oscillator, not by a separate object (p5 has one because it can
## modulate any parameter; here the target is unique). Reading it returns a map.
var osE = sound.sine(440)
assert(osE.envelope().attack == 0.01 and osE.envelope().sustain == 0.7)
assert(osE.envelope(0.02, 0.1, 0.5, 0.3) == osE)
var envE = osE.envelope()
assert(envE.attack == 0.02 and envE.decay == 0.1 and envE.sustain == 0.5 and envE.release == 0.3)

## trigger makes the voice audible and release lets it go — the dying away belongs to the mixer,
## hence to the browser, the integration container having no output. The curve's shape is checked
## through the buffers, which apply the SAME function.
assert(not osE.isPlaying())
assert(osE.trigger(0.2) == osE and osE.isPlaying())
assert(osE.release() == osE)

## With no envelope an oscillator behaves as it did before envelopes existed: start and stop alone.
var osSansE = sound.saw(100)
assert(osSansE.start().isPlaying())
osSansE.stop()

## ── The sound module: computed buffers ─────────────────────────────────────
## A buffer is a sound COMPUTED once, then triggered. Its accessors are what makes the synthesis
## checkable with no sound card: the samples are read instead of being listened to.
var bufT = sound.tone(1, 1.0)
assert(math.abs(bufT.duration() - 1.0) < 0.001)
assert(math.abs(bufT.peak() - 1.0) < 0.001)

## A 1 Hz sine over one second passes through 0, +1, 0 and -1 at the quarter turns: it is the
## wave's very shape that is checked, not merely the presence of a buffer.
assert(math.abs(bufT.sample(0)) < 0.001)
assert(math.abs(bufT.sample(0.25) - 1.0) < 0.001)
assert(math.abs(bufT.sample(0.5)) < 0.001)
assert(math.abs(bufT.sample(0.75) + 1.0) < 0.001)

## Outside the buffer a sample is zero — the silence around it, rather than an error.
assert(bufT.sample(-1) == 0 and bufT.sample(99) == 0)

## sound.generate samples an Ollin FORMULA, once, outside the audio callback.
var bufG = sound.generate(0.5, func(t) return 0.5 end)
assert(math.abs(bufG.duration() - 0.5) < 0.001)
assert(math.abs(bufG.peak() - 0.5) < 0.001)
assert(math.abs(bufG.sample(0.1) - 0.5) < 0.001)

## A value outside [-1;1] is brought back into range: beyond it, the output would clip.
assert(math.abs(sound.generate(0.1, func(t) return 5 end).peak() - 1.0) < 0.001)

## The envelope applied to the samples is the SAME function the mixer uses, so this test also
## validates the oscillators' curve — which nothing else can check here.
var bufE = sound.generate(1.0, func(t) return 1 end)
bufE.envelope(0.1, 0.2, 0.5, 0.25)
assert(math.abs(bufE.sample(0.05) - 0.5) < 0.01)    ## mi-attaque
assert(math.abs(bufE.sample(0.1) - 1.0) < 0.01)     ## sommet de l'attaque
assert(math.abs(bufE.sample(0.2) - 0.75) < 0.01)    ## mid-decay, between 1 and the sustain
assert(math.abs(bufE.sample(0.5) - 0.5) < 0.01)     ## maintien
assert(bufE.sample(0.999) < 0.01)                   ## the release has run out along with the sound

## Playback: play and stop, and the settings chain as an oscillator's do.
assert(not bufE.isPlaying())
assert(bufE.play().isPlaying())
assert(bufE.volume(0.3).pan(0.5).rate(2).volume() == 0.3)
assert(bufE.pan() == 0.5 and bufE.rate() == 2)
assert(bufE.loop() == bufE)
bufE.stop()
assert(not bufE.isPlaying())

## Named notes: equal temperament around A 440, with no table of frequencies copied out. A NAME is
## accepted wherever a frequency is, so a single point of passage in the engine covers sound.osc,
## sound.tone and osc.freq.
assert(math.abs(sound.note("A4") - 440.0) < 0.01)
assert(math.abs(sound.note("a4") - 440.0) < 0.01)      ## the case does not matter
assert(math.abs(sound.note("C4") - 261.626) < 0.01)
assert(math.abs(sound.note("A0") - 27.5) < 0.01)
assert(math.abs(sound.note("C-1") - 8.1758) < 0.001)   ## the lowest octave

## A sharp and a flat give the same pitch when they name the same note.
assert(math.abs(sound.note("C#4") - sound.note("Db4")) < 0.001)

## All three places a frequency is used accept the name.
assert(math.abs(sound.osc("A4").freq() - 440.0) < 0.01)
assert(math.abs(sound.sine(100).freq("E4").freq() - 329.628) < 0.01)
assert(math.abs(sound.tone("A5", 0.1).duration() - 0.1) < 0.001)

## ── The touch module (multitouch) ──────────────────────────────────────────
## With no touch surface — which is the integration container's case — the module still exists: a
## script reading the state runs and sees nothing, instead of failing on a nil.
assert(typeof(touch) == "map")
assert(touch.count() == 0)
assert(typeof(touch.points()) == "array" and #touch.points() == 0)

## The callbacks are assigned as `mouse`'s are: the engine calls whatever exists, and the absence
## of all three is not a fault.
global tcVus = []
func touch.began(id, x, y)
    tcVus[#tcVus + 1] = id
end
assert(#tcVus == 0)

## ── The audio module (the session) ─────────────────────────────────────────
## The module ALWAYS exists, device or no device: generating waves is pure computation, and the
## suite runs in a container with no sound card. Only the output is mute.
assert(typeof(audio) == "map")
assert(audio.sampleRate() == 44100)

## With no device, start() returns false and isReady() stays false — without throwing.
var auPret = audio.start()
assert(typeof(auPret) == "bool")
assert(audio.isReady() == auPret)

## The volume reads back as it was set, and is clamped to [0;1] silently: beyond it the output
## would clip, so we correct instead of refusing, as with a colour component.
assert(audio.volume(0.25) == 0.25)
assert(audio.volume() == 0.25)
assert(audio.volume(9) == 1)
assert(audio.volume(-3) == 0)
audio.volume(1)

## Pause belongs to the SESSION: it suspends the mix's PROGRESS, where a zero volume would let
## everything run on in silence and make the sound resume further along.
assert(not audio.isPaused())
audio.pause()
assert(audio.isPaused())
audio.resume()
assert(not audio.isPaused())

## Equality by IDENTITY for the reference types. Only maps were covered: two variables naming the
## same array compared as unequal, and `a <> a` was true.
var idTab = [1, 2]
var idTabAlias = idTab
assert(idTab == idTabAlias)
assert(not (idTab <> idTabAlias))
assert(idTab <> [1, 2])          ## contenu identique, objets distincts
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

## `free()` gives the voice back to the engine AND makes the handle stale: reusing it must be
## reported, not silently ignored. Without that explicit release, every polyphonic script had to
## pre-allocate a pool, for want of knowing when a stopped slot would be recycled.
var oscLibre = sound.sine(440)
oscLibre.free()
var perime = false
try
    oscLibre.freq(880)
catch e
    perime = true
end
assert(perime)
## A voice given back with NO envelope is free at once: as many can be created as the table
## holds, one after another.
for i = 1, 40 do
    sound.sine(220 + i).free()
end
## A slot is only protected while something makes it SOUND. With no audio output — a headless
## build, or the browser before the first gesture — no envelope ever finishes, so a voice given
## back by free() must become available at once: otherwise the seventeenth creation failed with
## "no oscillator available", although every voice had indeed been released.
for i = 1, 20 do
    var v = sound.sine(330 + i).envelope(0.01, 0.05, 0.5, 5.0)
    v.trigger(0.05)
    v.free()
end
var autre = sound.sine(660)
assert(autre.isPlaying() == false)
autre.free()

print("regressions ok")
