## Regression tests — Classes and instances: super, meta-methods, __str, constructors.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/classes.ol — it must finish without error.

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

## ── VM: a meta-method call in a loop must not leak registers ────────────────
## (before: try_meta_binary/try_meta_unary push their frame at regs.size(), and neither
## op_RETURN nor finish_return (RETURN_V/RETURN_SPREAD) ever gave that space back — every
## `a + b` on instances permanently consumed a few registers, overflowing the 4096-register
## budget after a few hundred calls, with no recursion in sight. Two shapes are exercised: a
## meta-method body returning a scalar (plain RETURN) and one returning a freshly constructed
## instance (RETURN_V/RETURN_SPREAD), which leaked independently.
class LeakScalar
    func init(x) self.x = x end
    func __add(o) return self.x + o.x end   ## plain RETURN
end
var lsA = LeakScalar(1)
var lsB = LeakScalar(2)
var lsAcc = 0
for i in [1;2000] do
    lsAcc += lsA + lsB
end
assert(lsAcc == 6000)

class LeakCtor
    func init(v) self.v = v end
    func __add(o) return LeakCtor(self.v + o.v) end   ## RETURN_V: the value is a call
    func __neg()  return LeakCtor(-self.v) end
    func __eq(o)  return self.v == o.v end
end
var lc = LeakCtor(1)
var lcOther = LeakCtor(1)
for i in [1;2000] do
    lc = lc + LeakCtor(1)
    var negated = -lc                 ## RETURN_V again, through try_meta_unary
    var eqCheck = lc == lcOther       ## negate_result path, through <>
    var neqCheck = lc <> lcOther
end
assert(lc.v == 2001)

## ── VM: concatenation with __str, and no use-after-free ─────────────────────
class StrP
    func __str() return "SP" end
end
assert("x=" + StrP() == "x=SP")

## A __str that returns something other than a string is DESCRIBED, never dropped: a boolean,
## an array or a map used to yield the empty string in silence.
class StrBool
    func __str() return true end
end
class StrArr
    func __str() return [1, 2] end
end
class StrNum
    func __str() return 42 end
end
assert("[" + StrBool() + "]" == "[true]")
assert("[" + StrArr() + "]" == "[\{array}]")
assert("[" + StrNum() + "]" == "[42]")

## the other values a `__str` may hand back are named by their kind
class StrMap
    func __str() return {a: 1} end
end
class StrRange
    func __str() return [1;3] end
end
class StrFunc
    func __str() return func() end end
end
class StrClassValue
    func __str() return StrNum end
end
assert("[" + StrMap() + "]" == "[\{map}]" and "[" + StrRange() + "]" == "[\{range}]")
assert("[" + StrFunc() + "]" == "[\{function}]" and "[" + StrClassValue() + "]" == "[\{class}]")

## A `__str` that RETURNS NOTHING reads "nil", the value its result slot holds — the same answer
## whether it is written in Ollin or native, since both now go down one road.
class StrVoid
    func __str() return end
end
assert("[" + StrVoid() + "]" == "[nil]")

## A CLASS passes is_callable but is not a `__str`: naming the class is all that can be said, and
## calling it would instantiate. Only the class NAME comes back.
class StrIsClass
end
StrIsClass.__str = StrP
assert("[" + StrIsClass() + "]" == "[\{StrIsClass}]")

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

## ── A constructor gives the OBJECT, and the COMPILER is what settles it ────
## `init` used to be a flag on the call frame: the VM saved self, popped, then rewrote the result
## in its three return paths. The compiler knows it is compiling an init, so every `return` there
## evaluates its values — they may have side effects — and hands back self, which sits in R[0].
class CtA
    func init(x)
        self.x = x
        if x > 10 then
            return "too big"     ## an explicit return in the middle: the object still wins
        end
        self.tag = "small"
        return 42
    end
end
class CtB
    func init()
        var f = func() return 7 end
        self.v = f()
    end
end

## a `return` inside a try inside a constructor: the handler must still be live for the value
class CtC
    func init(v)
        try
            self.v = v.field
            return
        catch e
            self.v = "caught"
        end
    end
end

## a multiple return from an init still yields the object, and nothing more
class CtD
    func init() return 1, 2, 3 end
end
func ctorChecks()
    var a1 = CtA(3)
    var a2 = CtA(99)
    assert(a1.x == 3 and a1.tag == "small")
    assert(a2.x == 99 and a2.tag == nil) ## the early return did leave the rest unrun
    assert(a1 <> 42 and a2 <> "too big")
    assert(CtC(1).v == "caught")
    assert(CtB().v == 7)                 ## a lambda inside a constructor keeps its own return value
    var g1, g2 = CtD()                   ## a multiple return still yields the object, and nothing more
    assert(g1 <> nil and g2 == nil)
end
ctorChecks()

## an optional call through super: the parent method is called when it is there
class SqBase
    func tag() return "base" end
end
class SqChild extends SqBase
    func tag() return super.tag?() end
end
assert(SqChild().tag() == "base")

print("regressions ok")
