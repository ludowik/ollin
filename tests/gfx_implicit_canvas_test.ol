## A draw() alone starts a graphics session (the implicit canvas) — EVEN when the script never writes the word
## `graphics`. The program only counts frames, and a program that does not name the module cannot call graphics.quit():
## it ends by an assertion that fails on the fifth frame, and tests/run_gfx.sh expects exactly that message.
## (execute() builds only the modules a script names; the entry hook has to ask for `graphics` itself.)
global frames = 0

func draw()
    frames += 1
    if frames == 5 then
        assert(false, "the implicit canvas started the loop")
    end
end
