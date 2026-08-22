## Persistence: the `data` module remembers values from one run to the next.
## Here a run counter, in the PROJECT scope, plus a score raised on every click.
## Relance le script (ou recharge la page) : le compteur et le score reviennent.

global runs = 0
global score = 0

func setup()
    graphics.canvas(W, H, "data — persistance")
    runs = data.get("runs", 0) + 1     ## read, then raised on every run
    data.set("runs", runs)
    score = data.get("score", 0)       ## taken up where it was left
end

func mouse.pressed(x, y)
    score = score + 1
    data.set("score", score)           ## persisted at once
end

func draw()
    graphics.clear(Color(0.10, 0.12, 0.18))
    graphics.stroke(colors.WHITE)
    graphics.fontSize(30)
    graphics.text("Lancement n° " + runs, 24, 40)
    graphics.stroke(colors.SKYBLUE)
    graphics.fontSize(26)
    graphics.text("Score (clique) : " + score, 24, 92)
    graphics.stroke(colors.GRAY)
    graphics.fontSize(16)
    graphics.text("Restart or reload: everything is kept.", 24, 150)
    graphics.stroke(colors.GRAY)
    graphics.fontSize(16)
    graphics.text("data.shared.* gives a scope shared between projects.", 24, 176)
end
