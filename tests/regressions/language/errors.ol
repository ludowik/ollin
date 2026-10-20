## Regression tests — Errors: try/catch, the handler stack, errors crossing native frames, the message of assert.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/errors.ol — it must finish without error.

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

## A CAUGHT error reaches the script as it was thrown, with NO source line — the message is data
## for the program, the location is for the developer reading a crash. It used to depend on the
## site of the throw: the engine's own errors carried a location, a builtin's did not.
global caughtEngine = "none"
try
    var nilThing = nil
    print(nilThing.field)
catch e
    caughtEngine = e
end
assert(caughtEngine == "cannot index nil with field 'field'")

## ── assert: the message is a string, and nothing else ──────────────────────
## A non-string used to be replaced by the generic wording, which threw the diagnosis away at the
## very moment it was needed. The type is checked EVEN WHEN the assertion holds, otherwise the
## mistake would hide until the day the assertion breaks.
try
    assert(true, 42)                     ## the condition is true, yet the message is wrong
    assert(false, "the wrong message was accepted")
catch e
    assert(e == "assert: the message must be a string")
end
try
    assert(false, 42)
catch e
    assert(e == "assert: the message must be a string")
end
try
    assert(false, "a real message")
catch e
    assert(e == "a real message")       ## a string message comes back untouched
end
try
    assert(false)
catch e
    assert(e == "assertion failed")
end

## A jump that LEAVES a try must pop its handler. Jumping over the POP_TRY left it on the VM's
## stack, and an error raised long after the loop was caught by it — the catch ran once per
## iteration the loop had made. Same defect for a `return` out of a try, on the VM side: the
## program then ended in SILENCE, with a status of 0, instead of reporting the error.
var tb = ""
for i = 1, 3 do
    try
        try
            if i == 2 then
                break
            end
            tb = tb + i
        catch e
            tb = tb + "c1"
        end
    catch e
        tb = tb + "c2"
    end
end
assert(tb == "1")

var tc = ""
for i = 1, 4 do
    try
        if i % 2 == 0 then
            continue
        end
        tc = tc + i
    catch e
        tc = tc + "C"
    end
end
assert(tc == "13")

func tr_return()
    try
        return "left"
    catch e
        return "caught"
    end
end
assert(tr_return() == "left")

## After all of the above, an error must still find the RIGHT handler — the one written here.
var tr_seen = ""
try
    var nothing = nil
    print(nothing.field)
catch e
    tr_seen = "here"
end
assert(tr_seen == "here")

## ── try/catch: the handler must live exactly as long as the block ──────────
## A `return` whose EXPRESSION fails inside a try: the handlers of the blocks being left were
## popped BEFORE the value was evaluated, so the error escaped its own try — while the same code
## written as `var v = ...` then `return v` was caught. They are popped after the evaluation now.
func trReturnRaises(x)
    try
        return x.champ
    catch e
        return "caught"
    end
end
assert(trReturnRaises(1) == "caught")

func trReturnTwoValues(x)
    try
        return 1, x.champ
    catch e
        return "caught"
    end
end
assert(trReturnTwoValues(1) == "caught")

## A callback run by a NATIVE higher-order function (array.map) lives in a nested dispatch loop.
## An error raised there was delivered to the enclosing catch AND then escaped at the end of the
## program: the nested loop resumed the enclosing program inside itself, and the native frame in
## between woke up with a truncated stack. Only the loop that owns the handler may unwind to it.
func cbErrorOutside()
    var t = [1, 2, 3]
    var seen = "none"
    try
        t.map(func(x) return x.champ end)
    catch e
        seen = e
    end
    return seen + "|" + t.reduce(func(a, b) return a + b end, 0)
end
assert(cbErrorOutside() == "cannot index int with field 'champ'|6")

## Same crossing for a script-level `throw`: the VALUE travels through the native frame.
func cbThrowOutside()
    var got = 0
    var pair = [1, 2]
    try
        pair.map(func(x) throw {code: 42} end)
    catch e
        got = e["code"]
    end
    return got
end
assert(cbThrowOutside() == 42)

## And a try INSIDE the callback is served on the spot, not by the enclosing one.
func cbTryInside()
    var r = [1, 2].map(func(x)
        try
            return x.champ
        catch e
            return -1
        end
    end)
    return r[1] + r[2]
end
assert(cbTryInside() == -2)

## __str also runs in a nested loop, through print.
class TrBoom
    func __str()
        var z = nil
        return z.x
    end
end
func cbStrRaises()
    var seen = "none"
    try
        print(TrBoom())
    catch e
        seen = e
    end
    return seen
end
assert(cbStrRaises() == "cannot index nil with field 'x'")

## Every place the ENGINE calls back into Ollin goes through one bridge, so an error raised in a
## callback must behave the same everywhere: caught once by the enclosing try, with the message as
## thrown, and the program carries on. The paths that need a screen (mouse, keyboard, touch, ui,
## image.mapPixel, draw) were probed by hand — under Xvfb and in the browser, where a raising
## mouse.pressed reports ONE error and stops instead of repeating it every click.
func cbRaises(f)
    try
        f()
        return "NOT RAISED"
    catch e
        return e
    end
end
func cbEveryBridge()
    var t = [3, 1, 2]
    assert(cbRaises(func() return t.map(func(x) return x.a end) end) == "cannot index int with field 'a'")
    assert(cbRaises(func() return t.filter(func(x) return x.a end) end) == "cannot index int with field 'a'")
    assert(cbRaises(func() return t.reduce(func(a, b) return a.x end, 0) end) == "cannot index int with field 'x'")
    ## the comparator's exception cannot cross stable_sort, so array_module captures and rethrows it
    assert(cbRaises(func() return t.sort(func(a, b) return a.x end) end) == "cannot index int with field 'x'")
    ## the sound generator samples an Ollin formula, off the audio thread
    assert(cbRaises(func() return sound.generate(0.01, func(s) return s.x end) end) ==
           "cannot index float with field 'x'")
    ## a `throw` crosses the same bridges, carrying its VALUE
    assert(cbThrows(func() return t.map(func(x) throw {code: 7} end) end) == 7)
    assert(cbThrows(func() return t.sort(func(a, b) throw {code: 8} end) end) == 8)
    ## and the array is still usable afterwards, the engine having left no half-state behind
    assert(t.reduce(func(a, b) return a + b end, 0) == 6)
end

func cbThrows(f)
    try
        f()
        return -1
    catch e
        return e["code"]
    end
end
cbEveryBridge()
