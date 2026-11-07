## Regression tests — Temporaries: a dead copy in a register must not keep a value alive.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/temporaries.ol — it must finish without error.

## ── Compiler: a statement empties its temporaries when the frame can outlive it ───────
## The bug: `global keep = []` builds the array in a temporary and copies it into the global. The
## temporary is not emptied when the statement ends, so after `keep = []` replaced the global the
## old array — now full of data — was still held by that register, and stayed so for as long as
## nothing wrote the register. A frame that runs for the whole program (the top level under a
## graphics loop, here the setup() entry hook) never does.
global dead_keep = []
global dead_before = 0
global dead_after = 0

func dead_fill()
    for i = 1, 20000 do
        dead_keep.push({a: i, b: "x" + i})
    end
end

func setup()
    dead_fill()
    dead_before = mem()
    dead_keep = []
    dead_after = mem()
    assert(dead_before - dead_after > 2000000, "the dropped array is still held: {dead_before} → {dead_after}")
end

## the same inside a function that holds a loop: the array handed over as the last of many arguments sits in a
## high temporary, which no later statement of that function writes
global loop_keep = nil
func loop_store(a, b, c, d, e, f, g, h)
    loop_keep = h
end
func loop_run()
    loop_store(1, 2, 3, 4, 5, 6, 7, [])
    for i = 1, 20000 do
        loop_keep.push({a: i, b: "y" + i})
    end
    var before = mem()
    loop_keep = []
    assert(before - mem() > 2000000, "the dropped array is still held by a function that holds a loop")
end
loop_run()
