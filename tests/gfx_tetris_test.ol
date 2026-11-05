## The two styles of the Tetris sample draw every screen, with and without the pads, without an error — the drawing is
## the part of the sample that no test without a window can run. It runs the sample itself (its setup and its draw) under
## Xvfb, and only its update is replaced here: one screen a frame, each in both styles, with the pads and without.
## tests/run_gfx.sh runs it; a failed drawing ends it with an error and a status that is not 0.

import "../docs/samples/tetris/tetris.ol"

## The contract of a style: what tetris.ol asks of it.
assert(len(styles) == 2 and styles[1].name <> styles[2].name)
for st in styles do
    for key in ["name", "font", "smooth", "ground", "game", "items", "pads"] do
        assert(st[key] <> nil, "the style {st.name} has no {key}")
    end
    assert(typeof(st.game) == "function" and typeof(st.items) == "function")
end

## A well half full of pieces, with long pieces side by side and stacked, and one falling.
func fillWell()
    game.well = newWell()
    for r = 9, 17 do
        for c = 0, 9 do
            if (c * 7 + r * 3) % 5 <> 0 then
                game.well[wellIdx(c, r)] = 1 + (c + r) % 7
            end
        end
    end
    for r = 5, 8 do
        game.well[wellIdx(1, r)] = Piece.I
    end
    for c = 3, 6 do
        game.well[wellIdx(c, 4)] = Piece.I
    end
    game.kind = Piece.T
    game.turn = 1
    game.x = 4
    game.y = 1
    game.next = Piece.S
    game.score = 6629
    game.level = 3
    game.lines = 33
    game.clearing = []
end

func playing()
    fillWell()
    game.state = "play"
end

func clearing()
    fillWell()
    game.state = "clearing"
    game.clearing = [16, 17]
    game.wait = config.clearFrames - config.clearFlash
end

func paused()
    fillWell()
    game.state = "paused"
    game.resume = "play"
end

func lost()
    fillWell()
    game.state = "over"
    game.won = false
    game.wait = 5 * config.curtainFrames
end

func lostAndDone()
    fillWell()
    game.state = "over"
    game.won = false
    game.newBest = false
    game.wait = overFrames()
end

func won()
    fillWell()
    game.state = "over"
    game.won = true
    game.newBest = true
    game.wait = overFrames()
end

func menuOn(focus, kind)
    game.state = "menu"
    game.focus = focus
    game.type = kind
end

func levelOn(kind)
    game.state = "level"
    game.focus = kind == "B" and "height" or "level"
    game.type = kind
    game.startLevel = 6
    game.height = 2
    game.best = 99999
end

global scenes = [
    func() game.state = "title" end,
    func() menuOn("type", "A") end,
    func() menuOn("music", "B") end,
    func() levelOn("A") end,
    func() levelOn("B") end,
    playing, clearing, paused, lost, lostAndDone, won
]
global frames = 0

func update(dt)
    frames += 1
    var count = len(scenes)
    var k = frames - 1
    if k >= 4 * count then
        graphics.quit()
        return
    end
    var combo = k // count
    view.style = combo % 2 + 1
    view.touchSeen = combo >= 2
    applyStyle()
    layoutCompute()
    game.frame = frames * 7
    scenes[k % count + 1]()
end
