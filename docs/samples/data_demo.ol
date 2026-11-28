## Persistence: the `data` module remembers values from one run to the next.
## Here a run counter, in the PROJECT scope, plus a score raised on every click.
## Restart the script (or reload the page): the counter and the score come back.

global runs = 0
global score = 0

func setup()
    gfx.canvas(W, H, "data - persistence")
    runs = data.get("runs", 0) + 1
    data.set("runs", runs)
    score = data.get("score", 0)
end

func mouse.pressed(x, y)
    score = score + 1
    data.set("score", score)
end

func draw()
    gfx.clear(Color(0.10, 0.12, 0.18))
    gfx.stroke(palette.WHITE)
    gfx.fontSize(30)
    gfx.text("Run no. " + runs, 24, 40)
    gfx.stroke(palette.SKYBLUE)
    gfx.fontSize(26)
    gfx.text("Score (click): " + score, 24, 92)
    gfx.stroke(palette.GRAY)
    gfx.fontSize(16)
    gfx.text("Restart or reload: everything is kept.", 24, 150)
    gfx.stroke(palette.GRAY)
    gfx.fontSize(16)
    gfx.text("data.shared.* gives a scope shared between projects.", 24, 176)
end
