## What a phone's keyboard really does, shown on the screen: the lines on the left are what the page saw —
## the focus it took and lost, the keys the keyboard sent, the size of the visible area — newest last, as keyboard.trace()
## gives them. Take a screenshot of it when something does not behave as it should.

global name = nil
global lastSubmit = "nothing validated yet"

ui.textField("Name", ref name, 24, "type here", func(text)
    lastSubmit = "validated: {text}"
end)
ui.open()

gfx.fitArea()

func draw()
    gfx.clear(Color(0.10, 0.12, 0.18))
    gfx.noStroke()
    var size = math.max(SIZE * 0.036, 11)
    gfx.font("mono")
    gfx.fontSize(size)
    gfx.fill(1, 1, 1)
    gfx.text(lastSubmit, W * 0.03, H * 0.16)
    gfx.fill(0.6, 0.65, 0.75)
    var lines = keyboard.trace(18).split("\n")
    for i = 1, #lines do
        gfx.text(lines[i], W * 0.03, H * 0.16 + size * 1.6 + (i - 1) * size * 1.3)
    end
end
