## ui_draw reads the list's bound variable through a script getter, one row after the other. A getter that
## calls ui.clear() kills the rows still to come, and drawing them read a reference that no longer
## existed: the engine crashed. Needs a frame loop, so it runs under Xvfb (tools/run-headless.sh) with
## the raylib build.

global wipe = false
global chosen = 1
global frames = 0
global pick = nil
var picker = {__ref: true, get: func() if wipe then ui.clear() end return chosen end, set: func(v) chosen = v end}

func setup()
    graphics.canvas(320, 240, "ui draw")
    pick = ui.list("Pick", [1, 2, 3, 4], picker)
    ui.open()
    pick.open()
end

func draw()
    graphics.clear(0.1, 0.1, 0.15)
    frames += 1
    if frames == 3 then
        wipe = true
    end
    if frames == 8 then
        graphics.quit()
    end
end
