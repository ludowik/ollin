## Connect Four against the computer: drop discs in a grid of seven columns by six rows, and be the first to line up four. The computer
## looks ahead with a search that picks the best of what it sees, to a depth that sets the level; the game in progress and the scores are
## kept between two runs.

import "play.ol"
import "screens.ol"
import "draw.ol"

func setup()
    gfx.canvas(W, H, "Connect Four")
    gfx.fitArea()
    fitView(window.width, window.height)
    loadScores()
    loadGame()
    buildSounds()
end

## The field for an area of w x h pixels.
func fitView(w, h)
    viewH = viewHeight(w, h)
    gfx.viewport(VIEW_W, viewH)
end

func window.resized(w, h)
    fitView(w, h)
end

func keyboard.pressed(key)
    keyPressed(key)
end

## A finger also emulates the mouse, and touch.count() tells the two apart (it is already counted when the mouse callback runs), so each
## gesture is followed by the path that knows about every finger.
func mouse.pressed(x, y)
    if touch.count() == 0 then
        pointerDown("mouse", x, y)
    end
end

func mouse.moved(x, y)
    if touch.count() == 0 then
        pointerMove("mouse", x, y)
    end
end

func mouse.released(x, y)
    if touch.count() == 0 then
        pointerUp("mouse", x, y)
    end
end

func touch.began(id, x, y)
    pointerDown(id, x, y)
end

func touch.moved(id, x, y)
    pointerMove(id, x, y)
end

func touch.ended(id, x, y)
    pointerUp(id, x, y)
end

func update(dt)
    releaseLostPointer(touch.count(), mouse.isDown())
    updateFrame(dt)
end

func draw()
    drawScreen()
end
