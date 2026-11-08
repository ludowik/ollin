## A ui text field drawn and edited in a frame loop (Xvfb, raylib build). The keys themselves cannot be injected here, so
## this checks what a frame can: that the edited and the idle rows draw, that the interface folding or the field being
## removed or cleared while it is edited ends the edit without a crash, and that a getter that clears the interface in
## the middle of a draw does not take the text row with it. The typing is driven in the browser, by
## tools/test-keyboard-browser.js.

global frames = 0
global name = ""
global field = nil
global second = nil
global wipe = false
var tricky = {__ref: true, get: func() if wipe then ui.clear() end return name end, set: func(v) name = v end}

func setup()
    graphics.canvas(320, 240, "ui text")
    field = ui.textField("Name", ref name, 10, "your name")
    second = ui.textField("Tricky", tricky)
    ui.open()
end

func draw()
    graphics.clear(0.1, 0.1, 0.15)
    frames += 1
    if frames == 2 then
        field.edit()
    elseif frames == 4 then
        ui.close()
    elseif frames == 5 then
        ui.open()
        field.edit()
    elseif frames == 7 then
        field.remove()
    elseif frames == 8 then
        second.edit()
    elseif frames == 10 then
        wipe = true
    elseif frames == 14 then
        assert(ui.current() <> nil)
        graphics.quit()
    end
end
