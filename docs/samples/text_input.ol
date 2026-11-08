## Typing text: keyboard.typed(text) gives what the keys WROTE (a capital, an accent, a hyphen), and keyboard.show() /
## keyboard.hide() raise and lower the keyboard of a phone, which a canvas cannot raise by itself. On a computer the
## physical keyboard needs no show(). Tap the box to type, tap elsewhere to stop; return and backspace come as key names.

global text = ""
global editing = false
global lastChunk = ""
global chunks = 0

func field()
    var w = math.min(W * 0.9, 520)
    var h = math.max(SIZE * 0.12, 48)
    return {x: CX - w / 2, y: H * 0.22, w: w, h: h}
end

func inside(box, x, y)
    return x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h
end

func openField()
    editing = true
    keyboard.show()
end

func closeField()
    editing = false
    keyboard.hide()
end

func mouse.pressed(x, y)
    if inside(field(), x, y) then
        openField()
    else
        closeField()
    end
end

func keyboard.typed(chars)
    if editing and len(text) < 200 then
        text += chars
        lastChunk = chars
        chunks += 1
    end
end

func keyboard.keypressed(key)
    if not editing then
        return
    end
    if key == "backspace" and len(text) > 0 then
        text = string.substr(text, 1, len(text) - 1)
    elseif key == "return" then
        closeField()
    end
end

graphics.fitArea()

func draw()
    graphics.clear(Color(0.10, 0.12, 0.18))
    var box = field()
    graphics.noStroke()
    graphics.fill(1, 1, 1, editing and 0.22 or 0.1)
    graphics.rect(box.x, box.y, box.w, box.h, box.h * 0.2)

    var size = box.h * 0.5
    graphics.fontSize(size)
    graphics.stroke(colors.WHITE)
    var shown = text
    if len(shown) > 22 then
        shown = string.substr(shown, len(shown) - 21, 22)
    end
    if editing and math.frac(elapsedTime) < 0.5 then
        shown += "_"
    end
    if shown == "" then
        graphics.stroke(0.6, 0.65, 0.75)
        shown = "tap to type"
    end
    graphics.text(shown, box.x + box.h * 0.3, box.y + box.h * 0.22)

    graphics.fontSize(math.max(SIZE * 0.035, 14))
    graphics.stroke(0.6, 0.65, 0.75)
    graphics.text("the keyboard is " + (editing and "asked for" or "down"), box.x, box.y + box.h * 1.4)
    graphics.text("typed(text) calls so far: " + chunks, box.x, box.y + box.h * 1.4 + SIZE * 0.06)
    graphics.text("the last one: " + lastChunk, box.x, box.y + box.h * 1.4 + SIZE * 0.12)
end
