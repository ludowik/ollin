## Coroutines: functions that suspend in the middle of their body and resume where they stopped, with `yield` and the `coroutine`
## module. The state model is in src/coroutine.h; these are the behaviours a script can see.

## ── The basics ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
var coBasic = coroutine.create(func()
    yield
    yield
    return "end"
end)
assert(typeof(coBasic) == "coroutine" and coroutine.status(coBasic) == "suspended", "a new coroutine is suspended")
assert(coroutine.resume(coBasic) == nil and coroutine.status(coBasic) == "suspended", "a bare yield hands nothing back")
assert(coroutine.resume(coBasic) == nil)
assert(coroutine.resume(coBasic) == "end" and coroutine.status(coBasic) == "dead", "the return value comes with the last resume")
var coKeyed = {}
coKeyed[coBasic] = 1
assert(coKeyed[coBasic] == 1 and coBasic == coBasic and coBasic <> coroutine.create(func() end), "a coroutine is its own key and equals only itself")
assert(not not coBasic, "a coroutine is true")

## ── Values in both directions ────────────────────────────────────────────────────────────────────────────────────────────────
var coTalk = coroutine.create(func(a, b)
    var x = yield a + b
    var y, z = yield x * 2
    return y, z, "last"
end)
assert(coroutine.resume(coTalk, 1, 2) == 3, "the first resume's values are the body's arguments, a yield hands its values out")
assert(coroutine.resume(coTalk, 10) == 20, "the next resume's values are what the yield returns")
var coA, coB, coC = coroutine.resume(coTalk, "p", "q")
assert(coA == "p" and coB == "q" and coC == "last", "several values go both ways")
var coMany = coroutine.create(func(...)
    var first, second = yield 1, 2, 3
    return first, second
end)
var coP, coQ, coR = coroutine.resume(coMany, "a")
assert(coP == 1 and coQ == 2 and coR == 3)
var coS, coT = coroutine.resume(coMany)
assert(coS == nil and coT == nil, "a resume with nothing leaves nil where the yield returns")

## ── Generators ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
func coFibonacci(n)
    return coroutine.create(func()
        var a = 0
        var b = 1
        for i = 1, n do
            yield a
            a, b = b, a + b
        end
    end)
end
var coGen = coFibonacci(10)
var coSeq = []
while coroutine.status(coGen) == "suspended" do
    var v = coroutine.resume(coGen)
    if v <> nil then
        coSeq.push(v)
    end
end
assert(coSeq.join(",") == "0,1,1,2,3,5,8,13,21,34", "a generator written as a loop")

## ── A yield may be anywhere in the calls the body makes ─────────────────────────────────────────────────────────────────────
func coDeep(n)
    if n == 0 then
        yield "bottom"
        return 0
    end
    return coDeep(n - 1) + 1
end
var coRec = coroutine.create(func()
    return coDeep(50)
end)
assert(coroutine.resume(coRec) == "bottom", "yield from fifty calls down")
assert(coroutine.resume(coRec) == 50, "and the whole stack comes back")

class CoWalker
    func init()
        self.n = 0
    end
    func step()
        self.n += 1
        yield self.n
    end
end
var coWalker = CoWalker()
var coMethod = coroutine.create(func()
    coWalker.step()
    coWalker.step()
end)
assert(coroutine.resume(coMethod) == 1 and coroutine.resume(coMethod) == 2, "a method that yields")

## ── Statuses and misuse ──────────────────────────────────────────────────────────────────────────────────────────────────────
var coSelf = nil
var coSeen = ""
coSelf = coroutine.create(func()
    coSeen = coroutine.status(coSelf)
    try
        coroutine.resume(coSelf)
    catch e
        coSeen = coSeen + "|" + e
    end
end)
coroutine.resume(coSelf)
assert(coSeen == "running|cannot resume a running coroutine", "a coroutine is running while it runs and cannot resume itself")
try
    coroutine.resume(coSelf)
    assert(false)
catch e
    assert(e == "cannot resume a dead coroutine")
end
var coOuter = nil
var coInner = nil
var coNormal = ""
coInner = coroutine.create(func()
    coNormal = coroutine.status(coOuter)
    yield
end)
coOuter = coroutine.create(func()
    coroutine.resume(coInner)
end)
coroutine.resume(coOuter)
assert(coNormal == "normal", "a coroutine that resumed another is normal while that one runs")
assert(coroutine.status(coInner) == "suspended" and coroutine.status(coOuter) == "dead")
try
    yield
    assert(false)
catch e
    assert(e == "yield outside a coroutine")
end
assert(coroutine.running() == nil and not coroutine.isYieldable(), "the main program is no coroutine")
var coRunning = nil
var coYieldable = nil
var coMe = coroutine.create(func()
    coRunning = coroutine.running()
    coYieldable = coroutine.isYieldable()
end)
coroutine.resume(coMe)
assert(coRunning == coMe and coYieldable, "running() names the coroutine that runs")

## ── Errors ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
var coBoom = coroutine.create(func()
    yield 1
    assert(false, "boom")
end)
coroutine.resume(coBoom)
try
    coroutine.resume(coBoom)
    assert(false, "the error must reach the resumer")
catch e
    assert(e == "boom", "the error arrives as it was thrown")
end
assert(coroutine.status(coBoom) == "dead", "an error kills the coroutine")
var coThrower = coroutine.create(func()
    throw {code: 7}
end)
try
    coroutine.resume(coThrower)
catch e
    assert(e.code == 7, "a thrown value arrives whole")
end

## A try inside the body survives a yield.
var coSafe = coroutine.create(func()
    try
        yield "inside"
        throw "late"
    catch e
        yield "caught " + e
    end
    return "after"
end)
assert(coroutine.resume(coSafe) == "inside")
assert(coroutine.resume(coSafe) == "caught late", "the handler is still there after a yield")
assert(coroutine.resume(coSafe) == "after")

## A yield cannot cross a native function.
var coNative = coroutine.create(func()
    return [1, 2].map(func(x)
        yield x
        return x
    end)
end)
try
    coroutine.resume(coNative)
    assert(false)
catch e
    assert(e == "cannot yield across a native call (array.map, sort, __str…)")
end
assert(coroutine.status(coNative) == "dead")
assert(coroutine.isYieldable() == false)

## create refuses what is no function.
try
    coroutine.create(5)
    assert(false)
catch e
    assert(e == "coroutine.create: expected a function")
end
try
    coroutine.resume(5)
    assert(false)
catch e
    assert(e == "coroutine.resume: expected a coroutine")
end

## ── What a coroutine captures ────────────────────────────────────────────────────────────────────────────────────────────────
var coCounter = 0
var coBump = coroutine.create(func()
    coCounter += 1
    yield
    coCounter += 10
end)
coroutine.resume(coBump)
assert(coCounter == 1, "the body writes a variable of the program")
coCounter = 5
coroutine.resume(coBump)
assert(coCounter == 15, "and sees what the program wrote meanwhile")

## A closure made inside a suspended coroutine shares the coroutine's variable, from outside.
var coGetSet = nil
var coShare = coroutine.create(func()
    var n = 1
    coGetSet = {
        get: func()
            return n
        end,
        set: func(v)
            n = v
        end
    }
    yield
    n += 100
    return n
end)
coroutine.resume(coShare)
assert(coGetSet.get() == 1)
coGetSet.set(7)
assert(coGetSet.get() == 7, "the variable is open in the coroutine's registers, and reachable from outside")
assert(coroutine.resume(coShare) == 107, "and the coroutine sees what the closure wrote")
assert(coGetSet.get() == 107, "a finished coroutine's variable lives on in the closure")

## A closure outliving a coroutine that is never finished.
var coKept = nil
func coMakeAndDrop()
    var co = coroutine.create(func()
        var secret = "kept"
        coKept = func()
            return secret
        end
        yield
        secret = "never"
    end)
    coroutine.resume(co)
end
coMakeAndDrop()
assert(coKept() == "kept", "the variable survives the coroutine that was dropped suspended")
var coAfter = coroutine.create(func()
    var other = "other"
    yield
end)
coroutine.resume(coAfter)
assert(coKept() == "kept", "and is not overwritten by what lives in the memory that was freed")

## One variable per iteration, inside a coroutine.
var coFuncs = []
var coLoop = coroutine.create(func()
    for i = 1, 3 do
        coFuncs.push(func()
            return i
        end)
        yield
    end
end)
while coroutine.status(coLoop) == "suspended" do
    coroutine.resume(coLoop)
end
assert(coFuncs[1]() == 1 and coFuncs[2]() == 2 and coFuncs[3]() == 3, "each turn has its own variable")

## Iteration state lives in the registers too.
var coIter = coroutine.create(func()
    for k, v in [10, 20, 30] do
        yield k + v
    end
    for key, val in {a: 1} do
        yield key + val
    end
end)
var coOut = []
while coroutine.status(coIter) == "suspended" do
    var got = coroutine.resume(coIter)
    if got <> nil then
        coOut.push(got)
    end
end
assert(coOut.join(",") == "11,22,33,a1", "a for loop goes on after the yield")

## ── Many coroutines ──────────────────────────────────────────────────────────────────────────────────────────────────────────
var coPool = []
for i = 1, 500 do
    var id = i
    coPool.push(coroutine.create(func()
        var total = 0
        for round = 1, 3 do
            total += id
            yield total
        end
        return total
    end))
end
var coSum = 0
for round = 1, 3 do
    for co in coPool do
        coSum += coroutine.resume(co)
    end
end
assert(coSum == (1 + 2 + 3) * (500 * 501 / 2), "each one kept its own total")
coPool = nil

## Created and dropped by the thousand, finished or not: nothing builds up.
var coBefore = mem()
for i = 1, 20000 do
    var co = coroutine.create(func()
        var list = [1, 2, 3]
        yield list
        yield list
    end)
    coroutine.resume(co)
    if i % 2 == 0 then
        coroutine.resume(co)
        coroutine.resume(co)
    end
end
assert(mem() < coBefore + 4000000, "dropped coroutines are freed")

## ── Limits ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
func coRunaway(n)
    return coRunaway(n + 1) + 1
end
var coDeepDive = coroutine.create(func()
    return coRunaway(0)
end)
try
    coroutine.resume(coDeepDive)
    assert(false)
catch e
    assert(e == "runtime: stack overflow in a coroutine (max 1024 registers)", "a coroutine's own, smaller limit")
end
assert(coroutine.status(coDeepDive) == "dead")
func coWithinMain(n)
    if n == 0 then
        return 0
    end
    return coWithinMain(n - 1) + 1
end
assert(coWithinMain(300) == 300, "the program's own stack is untouched")

## A coroutine that resumes another, which yields into it.
var coPing = nil
var coPong = nil
var coLog = []
coPong = coroutine.create(func()
    coLog.push("pong1")
    yield
    coLog.push("pong2")
end)
coPing = coroutine.create(func()
    coLog.push("ping1")
    coroutine.resume(coPong)
    coLog.push("ping2")
    yield
    coroutine.resume(coPong)
    coLog.push("ping3")
end)
coroutine.resume(coPing)
coLog.push("main")
coroutine.resume(coPing)
assert(coLog.join(",") == "ping1,pong1,ping2,main,pong2,ping3", "coroutines nest, and each goes on from its own yield")
