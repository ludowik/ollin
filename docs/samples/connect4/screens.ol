## What a touch, a click and a key do on each screen of Connect Four, with no drawing. The rectangles that decide what was hit are the ones
## the drawing uses (layout.ol). A disc is AIMED by pressing or moving over the grid and dropped when the finger lifts over it, so that a
## finger can choose the column and then let go; a click is both at once.

import "play.ol"
import "layout.ol"

global pointerId = nil      ## the finger or the mouse that is down on the grid

## A lift that was never seen must not leave the screen deaf to the next touch: with no finger and no button down, nobody holds the
## screen. Called every frame with what the engine says.
func releaseLostPointer(touches, mouseHeld)
    if pointerId <> nil and touches == 0 and not mouseHeld then
        pointerId = nil
    end
end

func chooseLevel(i)
    levelIdx = math.clamp(i, 1, #LEVELS)
    playSound(sndClick)
end

func toggleFirst()
    humanFirst = not humanFirst
    playSound(sndClick)
end

## Aims at the column an x is over; nothing happens past the grid.
func aim(x)
    var col = columnAt(x)
    if col <> nil then
        hover = col
    end
end

## A press on the title.
func pressTitle(x, y)
    var lay = titleLay()
    for i, r in lay.levels do
        if inRect(x, y, r) then
            chooseLevel(i)
            return
        end
    end
    if inRect(x, y, lay.first) then
        toggleFirst()
    elseif lay.cont <> nil and inRect(x, y, lay.cont) then
        continueGame()
    elseif inRect(x, y, lay.start) then
        newGame()
    end
end

## A press in a game: the grid is aimed at, the buttons act at once.
func pressPlay(id, x, y)
    var lay = playLay()
    if inBoardZone(lay, x, y) then
        pointerId = id
        aim(x)
    elseif inRect(x, y, lay.left) then
        undoMove()
    elseif inRect(x, y, lay.right) then
        goTitle()
    end
end

func pressOver(x, y)
    var lay = playLay()
    if inRect(x, y, lay.left) then
        newGame()
    elseif inRect(x, y, lay.right) then
        goTitle()
    end
end

## A finger, or the mouse, goes down at x, y. Only one at a time is followed; `id` can be 0, which is why it is compared and never tested.
func pointerDown(id, x, y)
    if pointerId <> nil then
        return
    end
    if state == "title" then
        pressTitle(x, y)
    elseif state == "play" then
        pressPlay(id, x, y)
    else
        pressOver(x, y)
    end
end

func pointerMove(id, x, y)
    if state == "play" and inBoardZone(playLay(), x, y) then
        aim(x)
    end
end

## It lifts: a disc is dropped in the column it is over, when it was aimed and is still over the grid.
func pointerUp(id, x, y)
    if pointerId == nil or pointerId <> id then
        return
    end
    pointerId = nil
    var lay = playLay()
    if state == "play" and inBoardZone(lay, x, y) then
        hover = columnAt(x)
        humanDrop(hover)
    end
end

func makeDigitColumns()
    var columns = {}
    for col = 1, COLS do
        columns["{col}"] = col
    end
    return columns
end

const DIGIT_COLUMN = makeDigitColumns()

func keyTitle(key)
    if key == "left" then
        chooseLevel(levelIdx - 1)
    elseif key == "right" then
        chooseLevel(levelIdx + 1)
    elseif key == "up" or key == "down" or key == "f" then
        toggleFirst()
    elseif key == "c" and resumable <> nil then
        continueGame()
    elseif key == "space" or key == "return" then
        newGame()
    end
end

func keyPlay(key)
    if key == "left" then
        moveHover(-1)
    elseif key == "right" then
        moveHover(1)
    elseif key == "space" or key == "return" or key == "down" then
        humanDrop(hover)
    elseif DIGIT_COLUMN[key] <> nil then
        hover = DIGIT_COLUMN[key]
        humanDrop(hover)
    elseif key == "u" or key == "backspace" then
        undoMove()
    elseif key == "escape" or key == "m" then
        goTitle()
    end
end

func keyOver(key)
    if key == "space" or key == "return" then
        newGame()
    elseif key == "escape" or key == "m" then
        goTitle()
    end
end

func keyPressed(key)
    if state == "title" then
        keyTitle(key)
    elseif state == "play" then
        keyPlay(key)
    else
        keyOver(key)
    end
end
