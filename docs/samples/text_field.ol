## Typing a text into the interface of the engine: ui.textField is a row of the interface that edits a string in place.
## On a phone the keyboard of the system comes up; on a computer the physical keyboard types. Return, or a touch anywhere
## else, validates the text and writes the variable; escape gives the edit up. While the field is edited it owns the
## keyboard, so keyboard.typed and keyboard.pressed are not called: they are the way to read the keys when no field is.

global name = nil           ## the field fills it with "" at once, and writes it again when a text is validated
global greeted = ""
global edits = 0

ui.textField("Name", ref name, 24, "your name", func(text)
    greeted = text
    edits += 1
end)
ui.open()

gfx.fitArea()

func draw()
    gfx.clear(Color(0.10, 0.12, 0.18))
    var size = math.max(SIZE * 0.08, 20)
    gfx.noStroke()
    gfx.fill(1, 1, 1)
    gfx.fontSize(size)
    gfx.text(greeted == "" and "Hello!" or "Hello, {greeted}!", W * 0.06, H * 0.35)
    gfx.fontSize(math.max(SIZE * 0.035, 14))
    gfx.fill(0.6, 0.65, 0.75)
    gfx.text("validated {edits} times", W * 0.06, H * 0.35 + size * 1.6)
    gfx.text("the variable holds: {name}", W * 0.06, H * 0.35 + size * 1.6 + SIZE * 0.06)
end
