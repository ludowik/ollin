## Regression tests — Scopes: lexical scope, shadowing, globals, closures and upvalues, the loop variable.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/scopes.ol — it must finish without error.

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
        var z = z + 100   ## the right-hand side reads the OUTER z (3)
        assert(z == 103)
    end
    return z              ## the outer one is untouched
end
assert(shadow_outer() == 3)

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

## A local, a parameter or an upvalue SHADOWS a top-level function of the same name AT THE CALL
## SITE too. func_table was consulted first, so a callback parameter named like an existing
## function called that function instead — while reading the same name as a value resolved right.
func shadowed() return "the global one" end
func callWith(shadowed)
    return shadowed()
end
assert(callWith(func() return "the parameter" end) == "the parameter")

## A closure declared in a NESTED block keeps the value it captured. The block's locals die at
## its end, so the upvalues opened on them are closed there — without that, the register went
## back to the temporaries and the next statement overwrote the captured value. One case per
## kind of block, plus the throw path, which leaves the body without running its end.
func capturedIn(kind)
    var f = nil
    if kind == 1 then
        var a = 42
        f = func() return a end
    end
    var i = 0
    while i < 1 do
        var b = 43
        if kind == 2 then
            f = func() return b end
        end
        i += 1
    end
    try
        var c = 44
        if kind == 3 then
            f = func() return c end
        end
        throw "leave the body early"
    catch e
        var d = 45
        if kind == 4 then
            f = func() return d end
        end
    end
    switch kind
    case 5
        var g = 46
        f = func() return g end
    end
    var pad1, pad2, pad3, pad4, pad5 = 1, 2, 3, 4, 5   ## reuses the freed registers
    return f() + pad1 - pad1
end
assert(capturedIn(1) == 42)
assert(capturedIn(2) == 43)
assert(capturedIn(3) == 44)
assert(capturedIn(4) == 45)
assert(capturedIn(5) == 46)

## Closing an upvalue does not un-share it: two closures over the same block local still see
## each other's writes afterwards.
global blockSet = nil
global blockGet = nil
do
    var shared = 1
    blockSet = func(v) shared = v end
    blockGet = func() return shared end
end
blockSet(9)
assert(blockGet() == 9)

## Two closures capturing the SAME name through an intermediate function share ONE upvalue in
## that intermediate: the index learned by the first capture used to be thrown away when the
## inner body finished compiling, so the second pushed a descriptor of its own (measured: two
## upvalues for one variable). They must still see each other's writes.
func upvalRelay()
    var shared = 1
    func middle()
        func write(v)
            shared = v
        end
        func read()
            return shared
        end
        write(7)
        return read()
    end
    return middle() + shared
end
assert(upvalRelay() == 14)

## A func declared in a BLOCK lives in a local register, at the top level as well as inside a
## function: deciding by "am I in a function" stored it as a global while binding it as a local,
## so the register stayed empty and taking the function as a value gave nil.
do
    func blockFunc() return 5 end
    var alias = blockFunc
    assert(alias() == 5)
    assert(blockFunc() == 5)
end

## A const belongs to its block. const_names_ was not restored, so a constant declared in a
## block forbade assigning an unrelated variable of the same name afterwards.
do
    const scopedConst = 1
    assert(scopedConst == 1)
end
var scopedConst = 2
scopedConst = 3
assert(scopedConst == 3)

## One variable PER TURN in a while loop, as in a for. The body of a while is a block, so it
## closes its upvalues at its end — but a `continue` leaves the body without running that end,
## and the closures of that turn went on sharing their register with the next turn's (10 30 30 40
## instead of 10 20 30 40). The continue path closes them on its own way back.
func perTurn(withContinue)
    var fs = []
    var i = 0
    while i < 4 do
        i += 1
        var x = i * 10
        fs.push(func() return x end)
        if withContinue and i == 2 then
            continue
        end
    end
    return fs[1]() + fs[2]() * 100 + fs[3]() * 10000
end
assert(perTurn(false) == 10 + 2000 + 300000)
assert(perTurn(true) == 10 + 2000 + 300000)

## A break leaves the body early too, and the closures of the last turn keep their value.
func breakTurn()
    var gs = []
    var j = 0
    while true do
        j += 1
        var y = j * 100
        gs.push(func() return y end)
        if j == 2 then
            break
        end
    end
    return gs[1]() + gs[2]()
end
assert(breakTurn() == 300)

## Two closures of the SAME turn still share their variable, closing or not.
global sameTurnGet = nil
global sameTurnSet = nil
var once = 0
while once < 1 do
    var v = 1
    sameTurnGet = func() return v end
    sameTurnSet = func(n) v = n end
    once += 1
end
sameTurnSet(8)
assert(sameTurnGet() == 8)

## A lambda hidden INSIDE an interpolation captures the loop variable like any other, so the
## walk that looks for one must descend into the interpolated expressions. The old walk listed
## the kinds of expression by hand and left the interpolation out, answering "there is one" by
## precaution; the answer now comes from the node itself, so it must stay exact both ways.
func checkLambdaInInterpolation()
    var out = []
    for i = 1, 3 do
        out.push("v={(func() return i * 10 end)()}")
    end
    assert(out[1] == "v=10")
    assert(out[3] == "v=30")

    var fns = []
    for i = 1, 3 do
        var label = "n={i}"        ## carries NO function: the registers may be recycled
        fns.push(func() return label end)
    end
    assert(fns[1]() == "n=1")      ## one variable per turn, unaffected by the recycling
    assert(fns[3]() == "n=3")
end
checkLambdaInInterpolation()

## ── Compiler: names read and written through upvalues and globals ──
## a local of the same name as an enum, anywhere in the program, keeps that enum from being folded into
## constants: reading its field stays a real lookup, here on the local and on the enum alike
enum CxCol
    Red = 1,
    Green
end
func cxShadowLocal()
    var CxCol = {Red: 100}
    return CxCol.Red
end
func cxShadowUp()
    var CxCol = {Red: 200}
    func inner()
        return CxCol.Red
    end
    return inner()
end
assert(cxShadowLocal() == 100 and cxShadowUp() == 200 and CxCol.Red == 1 and CxCol.Green == 2)
## a PARAMETER of that name shadows it too. A separate enum: a `var` of the same name, as above, stops
## the enum from being a constant at all, and the shadow is then never even looked at
enum CxParamEnum
    Red = 1
end
func cxShadowParam(CxParamEnum)
    func inner()
        return CxParamEnum.Red
    end
    return CxParamEnum.Red + inner()
end
assert(cxShadowParam({Red: 40}) == 80 and CxParamEnum.Red == 1)

## a compound assignment whose right side is a variable, on an upvalue and on a global
var cxUp = 1
var cxAdd = 5
func cxBumpUp()
    cxUp += cxAdd
end
cxBumpUp()
assert(cxUp == 6)
global cxGl = 1
func cxBumpGl()
    cxGl += cxAdd
    return cxGl
end
assert(cxBumpGl() == 6)

## an upvalue passed as an argument
func cxShow(v)
    return v
end
func cxPassUp()
    return cxShow(cxUp)
end
assert(cxPassUp() == 6)
## a top-level function that captures a local is a closure: its NAME read as a value still finds it
var cxRef = cxBumpUp
cxRef()
assert(cxUp == 11)
## a callee that is an upvalue, called with a spread tail and with the optional form
var cxCb = func(...) return ... end
func cxViaUp(...)
    return cxCb(...)
end
func cxViaUpOpt()
    return cxCb?(4)
end
assert(cxViaUp(3) == 3 and cxViaUpOpt() == 4)
## `func holder.name()` on a variable reached as an upvalue
var cxHolder = {}
func cxDefine()
    func cxHolder.say()
        return "hi"
    end
end
cxDefine()
assert(cxHolder.say() == "hi")
## several indexed targets at once, through an upvalue and through a global
var cxMt = [0, 0]
func cxMultiIdx()
    cxMt[1], cxMt[2] = 5, 6
end
cxMultiIdx()
assert(cxMt[1] == 5 and cxMt[2] == 6)
global cxGt = [0, 0]
cxGt[1], cxGt[2] = 7, 8
assert(cxGt[1] == 7 and cxGt[2] == 8)
var cxTt = [0, 0]
func cxSetIdx()
    cxTt[1] = 5
    cxTt[2] += 1
end
cxSetIdx()
assert(cxTt[1] == 5 and cxTt[2] == 1)
var cxM1 = 0
var cxM2 = 0
func cxMulti()
    cxM1, cxM2 = 1, 2
end
cxMulti()
assert(cxM1 == 1 and cxM2 == 2)

## the loop variable stays a copy when the body shadows it or assigns it in a multiple assignment;
## a class or an enum declared in the body keeps the loop registers
var cxSeen = []
for i = 1, 2 do
    var i = 5
    cxSeen.push(i)
end
assert(cxSeen[1] == 5 and cxSeen[2] == 5)
var cxCount = 0
for i = 1, 2 do
    var j
    i, j = 7, 8
    cxCount += 1
end
assert(cxCount == 2)
var cxCls = []
for i = 1, 2 do
    class CxInner
        func f() return i end
    end
    cxCls.push(CxInner().f())
end
assert(cxCls[1] == 1 and cxCls[2] == 2)
var cxEn = 0
for i = 1, 2 do
    enum CxLoopEnum
        A
    end
    cxEn += CxLoopEnum.A
end
assert(cxEn == 2)
