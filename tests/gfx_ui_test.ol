## The `ui` module as the RAYLIB build runs it (build-gfx/ollin): the headless build has only a stub
## whose handles are inert, so nothing here can be seen from tests/run.sh's main binary.
## Declarations that run script code (a ref's getter or setter) are the delicate part: that code can
## remove the menu being declared into, call ui.clear, or grow the register file.

## A handle from before ui.clear stays stale. A cleared table used to restart every slot at
## generation 1, so the old handle designated whatever widget took its place.
var old = ui.menu("A")
ui.clear()
var fresh = ui.menu("B")
var stale = false
try
    old.button("x", func() end)
catch e
    stale = true
end
assert(stale, "a handle from before ui.clear must stay stale")

## A getter that removes the menu a slider is being declared into: the declaration is refused,
## instead of filing the widget under a dead (then recycled) parent.
var host = ui.menu("host")
var killer = {__ref: true, get: func() host.remove() return 1 end, set: func(v) end}
var refused = false
try
    host.slider("S", killer, 0, 10)
catch e
    refused = true
end
assert(refused, "declaring into a menu that a getter removed must be refused")

## A getter that calls ui.clear while a root widget is declared: the widget goes to the new root.
var wipe = {__ref: true, get: func() ui.clear() return 1 end, set: func(v) end}
ui.slider("W", wipe, 0, 10)
ui.button("after", func() end)

## The register file grows while a reference is read: the declaration must still read its own arguments.
func deep(n)
    if n == 0 then
        return 1
    end
    return deep(n - 1)
end
var bound = nil
var big = {__ref: true, get: func() deep(3000) return bound end, set: func(v) deep(3000) bound = v end}
ui.slider("S", big, 0, 10, 5)
assert(bound == 5, "the slider initialised the variable with its default")
bound = nil
ui.list("L", [7, 8, 9], big)
assert(bound == 7, "the list initialised the variable with its first item")
print("ui (raylib build): ok")
