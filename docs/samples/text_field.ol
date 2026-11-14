## Typing a text into the interface of the engine: ui.textField is a row of the interface that edits a string in place.
## On a phone the keyboard of the system comes up; on a computer the physical keyboard types. Return, or a touch anywhere
## else, validates the text and writes the variable; escape gives the edit up. While the field is edited it owns the keyboard, so keyboard.typed and
## keypressed are not called: they are the way to read the keys when no field is.

global name = nil           ## the field fills it with "" at once, and writes it again when a text is validated
global greeted = ""
global edits = 0

ui.textField("Name", ref name, 24, "your name", func(text)
    greeted = text
    edits += 1
end)
ui.open()

graphics.fitArea()

func draw()
    graphics.clear(Color(0.10, 0.12, 0.18))
    var size = math.max(SIZE * 0.08, 20)
    graphics.noStroke()
    graphics.fill(1, 1, 1)
    graphics.fontSize(size)
    graphics.text(greeted == "" and "Hello!" or "Hello, {greeted}!", W * 0.06, H * 0.35)
    graphics.fontSize(math.max(SIZE * 0.035, 14))
    graphics.fill(0.6, 0.65, 0.75)
    graphics.text("validated {edits} times", W * 0.06, H * 0.35 + size * 1.6)
    graphics.text("the variable holds: {name}", W * 0.06, H * 0.35 + size * 1.6 + SIZE * 0.06)
end
