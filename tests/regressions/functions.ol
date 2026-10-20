## Regression tests — Functions: multiple returns, destructuring, varargs and spreading, the registers a call must not clobber.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/functions.ol — it must finish without error.

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
    func two()
        return 8, 9
    end
end
var myObj = MyPair()
var maD1 = 0
var maD2 = 0
maD1, maD2 = myObj.two()
assert(maD1 == 8 and maD2 == 9)
func maVarargs(...)
    var maV1, maV2 = ...
    maV1, maV2 = ...
    assert(maV1 == "a" and maV2 == "b")
end
maVarargs("a", "b")

## A return that yields NO value still leaves nil where the caller reads its result. The slot
## kept whatever was there, so `var a = g()` on a bare `return` came back with a neighbouring
## register — a function value. The three return paths (RETURN, RETURN_V, RETURN_SPREAD) go
## through the same point, and last_results_ stays 0: the multi-value model is untouched, which
## the last two assertions check.
## Held in a FUNCTION rather than at the top level: its locals then live in its own frame, and
## the top level of this file is close to the 255-register limit.
class RetK
    func m()
        return
    end
end
func checkValuelessReturn()
    func retNone()
        return
    end
    func retImplicit()
        var unused = 1
    end
    func retSpread()
        return retNone()
    end
    func twoArgs(a, b)
        return "" + a + "|" + b
    end
    var rn = retNone()
    var ri = retImplicit()
    var rs = retSpread()
    assert(rn == nil and ri == nil and rs == nil)
    var rd, re = retNone()
    assert(rd == nil and re == nil)
    assert(RetK().m() == nil)
    ## Zero values REMAIN zero values where the count matters: an array literal ending on such a
    ## call is empty, and a non-final argument is adjusted to exactly one nil (the Lua model).
    assert(#[retNone()] == 0)
    assert(twoArgs(retNone(), "tail") == "nil|tail")
end
checkValuelessReturn()

## ── Multi-value expansion on a METHOD call ──────────────────────────────────
## The rule held everywhere but here: `obj.m(...)` was adjusted to ONE value, silently. The layout
## is the reason — an expansion rides on a call to a VALUE, while only a method call can decide
## whether the receiver takes `self` — so what is checked below is that BOTH hold at once.
##
## The declarations stay at the TOP level, where a class and a `func` cost no register, and the
## locals live in one function with a budget of its own: this file is close to the 255 registers
## the top level allows, and a peak reached inside a `do` block counts just the same.
class SinkVa
    func init()
        self.seen = []
    end
    func take(...)
        for v in [...] do
            self.seen.push(v)
        end
        return #self.seen
    end
    func three(a, b, c)
        return "{a}/{b}/{c}"
    end
end

class VaBase
    func init()
        self.log = ""
    end
    func note(...)
        for v in [...] do
            self.log = self.log + "{v}"
        end
        return self.log
    end
end
class VaChild extends VaBase
    func note(...)
        return "[" + super.note(...) + "]"
    end
end
class VaTwo
    func go(...)
        return ...
    end
end

global vaMap = {}
global vaOpt = {}
global vaCount = 0
global vaArr = [1, 2, 3]

func vaPair()
    return 10, 20
end
func vaIdx()
    return 2, 99
end
func vaCounted()
    vaCount += 1
    return 1, 2
end
func vaFwd(...)
    return SinkVa().take(...)
end
func vaFwd2(...)
    return vaMap.join(...)
end
func vaFwd3(...)
    return "abcdef".substr(...)
end
func vaFwd4(...)
    return VaTwo().go(...)
end

## A variadic function must keep its `...` across a NESTED call. It did not: a callee's registers
## start at the call base and run for its own reg_count, which can reach past the caller's own —
## and that is exactly where the caller's varargs live. A register-hungry callee therefore
## overwrote them, and `...` read back that callee's leftovers, silently. Found through the method
## expansion below, whose callee happened to be hungry enough to show it.
func vaFat(a)
    var t1 = a + 1
    var t2 = t1 + a
    var t3 = t2 + t1
    var t4 = t3 + t2
    var t5 = t4 + t3
    var t6 = t5 + t4
    var t7 = t6 + t5
    var t8 = t7 + t6
    var t9 = t8 + t7
    return t9 + t8
end
func vaAfterNested(...)
    var used = vaFat(1)
    var out = ""
    for v in [...] do
        out = out + "[" + "{v}" + "]"
    end
    return out + "/{used}"
end
func vaInner(...)
    var t1 = 1
    var t2 = t1 + 1
    var t3 = t2 + 1
    var t4 = t3 + 1
    var out = ""
    for v in [...] do
        out = out + "{v}"
    end
    return out
end
func vaAfterVariadic(...)
    var inner = vaInner(7, 8, 9, 10, 11)
    var out = ""
    for v in [...] do
        out = out + "[" + "{v}" + "]"
    end
    return out + "/" + inner
end

func vaBuiltinTail(...)
    return "{math.max(0, ...)}/{math.min(...)}"
end

class VaFwd
    func take(...)
        return vaInner(...)
    end
end
## A vararg tail forwarded through a METHOD, with a live method call before it: three variadic
## frames at once (this function, take, vaInner), and the innermost one's window plus its own
## vararg area reach past the OUTERMOST one's varargs. Lifting only the immediate caller's buried
## them: vaInner read back 1, 1, 9 for 7, 8, 9, and this function's own `...` was gone too.
func vaThreeDeep(...)
    var vaFwd = VaFwd()
    var first = vaFwd.take(1)
    var second = vaFwd.take(...)
    var out = ""
    for v in [...] do
        out = out + "[" + "{v}" + "]"
    end
    return first + "/" + second + "/" + out
end

class VaSix
    func init(a, b, c, d, e, f)
        self.first = a
    end
end
func vaAfterClass(...)
    var o = VaSix(1, ...)
    var out = ""
    for v in [...] do
        out = out + "[" + "{v}" + "]"
    end
    return out + "/{o.first}"
end

func vaCheck()
    assert(vaAfterNested(1, 2, 3) == "[1][2][3]/144")   ## the varargs survived the nested call
    ## And survived a callee that is ITSELF variadic: its vararg area starts above its register
    ## window and reaches further, so lifting to the window's end alone was not enough.
    assert(vaAfterVariadic(1, 2, 3) == "[1][2][3]/7891011")
    ## And survived instantiating a CLASS with a `...` tail: that path writes its arguments at the
    ## static register, past the slots the compiler reserved, so it wrote over the caller's own
    ## varargs BEFORE any frame was pushed — `f(7, 8, 9, 10, 11)` read back 11, 8, 9, 10, 11.
    assert(vaAfterClass(7, 8, 9, 10, 11) == "[7][8][9][10][11]/1")
    ## Three variadic frames live at once — see vaThreeDeep. The outermost frame's varargs are the
    ## ones that were lost, so the assertion checks BOTH what the innermost call received and what
    ## the outer `...` still reads afterwards.
    assert(vaThreeDeep(7, 8, 9) == "1/789/[7][8][9]")
    ## A BUILTIN under a `...` tail: the branch the abandoned fresh area used to size its result
    ## slots for. It is reachable without graphics, unlike a builtin returning TWO values under a
    ## tail (`var w, h = graphics.textSize(...)`), which only the Xvfb run can exercise.
    assert(vaBuiltinTail(3, 9, 4) == "9/3")

    ## Declared HERE, not at the top level: `func obj.field(...)` is a lambda assigned to a field,
    ## so it takes a register, and this file leaves none to spare up there.
    func vaMap.join(...)
        var out = ""
        for v in [...] do
            out = out + "{v}"
        end
        return out
    end
    func vaOpt.one(a, b)
        return "{a},{b}"
    end

    assert(vaFwd(1, 2, 3) == 3)      ## self injected AND three varargs arrived
    assert(vaFwd() == 0)             ## no vararg at all
    var sink = SinkVa()
    assert(sink.three(1, vaPair()) == "1/10/20")   ## a call in last position
    assert(sink.take(vaPair()) == 2)               ## a call as the only argument

    ## A MAP member takes no self, so its arguments must NOT be shifted by one.
    assert(vaFwd2(1, 2, 3) == "123")
    assert(vaMap.join(vaPair()) == "1020")

    ## A native method of a string and of an array.
    assert(vaFwd3(2, 3) == "bcd")
    vaArr.insert(vaIdx())
    assert(vaArr[2] == 99)

    ## `super` goes through the same compiler path, so it expands too.
    assert(VaChild().note(7, 8) == "[78]")

    ## An OPTIONAL call is the exception: its arguments stay unevaluated, so a multi-value tail is
    ## adjusted to one value instead of expanding.
    assert(vaOpt.one?(vaCounted()) == "1,nil")
    assert(vaCount == 1)
    assert(vaOpt.missing?(vaCounted()) == nil)
    assert(vaCount == 1)             ## a missing method evaluates nothing at all

    ## The expansion survives a multi-return, and nests.
    var a, b, c = vaFwd4(4, 5, 6)
    assert(a == 4 and b == 5 and c == 6)
    var two = VaTwo()
    assert(two.go(two.go(1, 2)) == 1)
    print("method-call expansion ok")
end
vaCheck()
