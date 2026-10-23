## Regression tests — Control flow: switch, break and continue, loops.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/control.ol — it must finish without error.

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

## A switch does not catch a `continue`: it reaches the enclosing loop. Only `break` is refused
## inside a switch (test_errors.sh), a case not falling through — so the two statements are
## deliberately asymmetric, and this pins the half that still works.
var sw_cont = ""
for i = 1, 4 do
    switch i
        case 2, 3
            continue
    end
    sw_cont = sw_cont + i
end
assert(sw_cont == "14")

## A loop nested INSIDE a switch arm keeps its own break: the refusal above must not reach it.
var sw_inner = ""
switch 1
    case 1
        for i = 1, 5 do
            if i == 3 then
                break
            end
            sw_inner = sw_inner + i
        end
end
assert(sw_inner == "12")

## A switch whose case values are all integers known at compile time jumps through a TABLE
## instead of comparing arm by arm. The table is invisible, so what is pinned here is that
## nothing it changes hands: an unmatched value, a hole in the span, a value repeated across
## arms, a negative value, a float subject (equality merges INTEGER and FLOAT, so `4 / 2` must
## reach `case 2`), a subject of another type, and an instance whose `__eq` decides — the last
## being the reason the comparison chain is still emitted as a slow path.
func swPick(k)
    switch k
    case 1
        return "un"
    case 2, 3
        return "deux-trois"
    case 7                     ## a hole: 4, 5 and 6 have no arm
        return "sept"
    case -2
        return "moins-deux"
    case 1
        return "jamais"        ## a repeated value belongs to the FIRST arm
    end
    return "autre"
end
assert(swPick(1) == "un" and swPick(2) == "deux-trois" and swPick(3) == "deux-trois")
assert(swPick(7) == "sept" and swPick(-2) == "moins-deux")
assert(swPick(5) == "autre" and swPick(99) == "autre" and swPick(-9) == "autre")
assert(swPick(4 / 2) == "deux-trois")   ## a division is a FLOAT, and 2.0 == 2
assert(swPick(2.5) == "autre" and swPick("2") == "autre" and swPick(nil) == "autre")

class SwNum
    func init(v) self.v = v end
    func __eq(o) return self.v == o end
end
assert(swPick(SwNum(7)) == "sept")      ## the meta-method decides, through the slow path
assert(swPick(SwNum(42)) == "autre")

enum SwTile GRASS = 0, ROCK, WATER end  ## an enum member is folded, so the table covers it
func swKind(t)
    switch t
    case SwTile.GRASS
        return "grass"
    case SwTile.WATER
        return "water"
    end
    return "?"
end
assert(swKind(SwTile.GRASS) == "grass" and swKind(SwTile.WATER) == "water")
assert(swKind(SwTile.ROCK) == "?")

var swAcc = 0                  ## a continue still traverses the switch and reaches the loop
for i = 1, 6 do
    switch i
    case 2
        continue
    case 5
        continue
    end
    swAcc = swAcc + i
end
assert(swAcc == 14)

## A switch whose case values reach the bounds of the 64-bit integer: the span between them
## overflows a signed subtraction, and the wrapped value used to pass the table's size test —
## the compiler then tried to allocate a vector of that size. It falls back to the chain.
func swWide(k)
    switch k
    case -9223372036854775807
        return "min"
    case 9223372036854775807
        return "max"
    end
    return "autre"
end
assert(swWide(-9223372036854775807) == "min")
assert(swWide(9223372036854775807) == "max")
assert(swWide(1) == "autre")

## A case value may be a variable: the branch is then found by the chain of comparisons, not the table
var cxKey = 2
var cxHit = "none"
switch 2
case cxKey
    cxHit = "variable"
else
    cxHit = "else"
end
assert(cxHit == "variable")
## a switch with no case at all runs its else
switch 3
else
    cxHit = "only else"
end
assert(cxHit == "only else")

## A numeric for with a float bound or step runs on doubles: forward, backward, and not at all
var cxFwd = 0
for x = 0.5, 2.5 do
    cxFwd += x
end
assert(cxFwd == 4.5)
var cxBack = []
for x = 2, 0.5, -0.5 do
    cxBack.push(x)
end
assert(#cxBack == 4 and cxBack[1] == 2 and cxBack[4] == 0.5)
var cxNone = 0
for x = 3.5, 1.5 do
    cxNone += 1
end
assert(cxNone == 0)
