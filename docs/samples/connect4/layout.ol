## Where everything is on Connect Four's screen, with no drawing: the playing field is VIEW_W pixels wide and as tall as the shape of the
## area asks, and what is on it is laid out from the middle outwards, so that a tall phone screen and a wide one both look right.

import "board.ol"
import "../lib/area.ol"

const VIEW_W = 400
const VIEW_MIN = 600
const VIEW_MAX = 800
const CELL = 52                 ## the side of a square of the grid
const BOARD_W = COLS * CELL
const BOARD_H = ROWS * CELL
const PANEL_PAD = 8             ## the blue of the grid goes this far past the squares
const BOARD_X = (VIEW_W - BOARD_W) // 2
const HEADER_H = 64
const AIM_H = CELL              ## the strip above the grid where the disc is held before it is dropped
const STATUS_H = 36
const BUTTON_H = 52
const GAP = 10
const MARGIN = 24

## The height of the field for an area of w x h pixels: as tall as its shape asks, within bounds.
func viewHeight(w, h)
    return fitHeight(VIEW_W, w, h, VIEW_MIN, VIEW_MAX)
end

## The room the screen of a game takes, in pixels.
const PLAY_H = HEADER_H + GAP + AIM_H + BOARD_H + 2 * PANEL_PAD + GAP + STATUS_H + GAP + BUTTON_H + MARGIN

## The screen of a game, in a field `viewH` tall: the header, the strip where the disc is held, the grid, the line that says what is
## going on, and two buttons under it.
func playLayout(viewH)
    var y = (viewH - PLAY_H) // 2
    var lay = {headerY: y}
    y += HEADER_H + GAP
    lay.aimTop = y
    lay.aimY = y + AIM_H / 2
    y += AIM_H
    lay.panel = rectOf(BOARD_X - PANEL_PAD, y, BOARD_W + 2 * PANEL_PAD, BOARD_H + 2 * PANEL_PAD)
    lay.boardY = y + PANEL_PAD
    y += BOARD_H + 2 * PANEL_PAD + GAP
    lay.statusY = y + STATUS_H / 2
    y += STATUS_H + GAP
    var w = (lay.panel.w - GAP) // 2
    lay.left = rectOf(lay.panel.x, y, w, BUTTON_H)
    lay.right = rectOf(lay.panel.x + w + GAP, y, w, BUTTON_H)
    return lay
end

## The screen before a game: the title, a button for each of `levelCount` levels, who plays first, the scores of the level shown, and the
## buttons. `resumable` says whether there is a game to go on with, which then has a button of its own above the one for a new game.
func titleLayout(viewH, levelCount, resumable)
    var top = (viewH - VIEW_MIN) // 2
    var x = BOARD_X - PANEL_PAD
    var w = BOARD_W + 2 * PANEL_PAD
    var lay = {titleY: top + 78, subtitleY: top + 124, levels: []}
    var each = (w - (levelCount - 1) * GAP) // levelCount
    for i = 1, levelCount do
        lay.levels.push(rectOf(x + (i - 1) * (each + GAP), top + 168, each, 56))
    end
    lay.first = rectOf(x, top + 238, w, BUTTON_H)
    lay.scores = rectOf(x, top + 304, w, 124)
    if resumable then
        lay.cont = rectOf(x, top + 446, w, 56)
        lay.start = rectOf(x, top + 514, w, 56)
    else
        lay.start = rectOf(x, top + 470, w, 64)
    end
    return lay
end

## The column that an x in the field is over, or nil when it is past the grid on either side. It does not depend on the height of the
## field: the grid is as wide on every screen.
func columnAt(x)
    if x < BOARD_X - PANEL_PAD or x > BOARD_X + BOARD_W + PANEL_PAD then
        return nil
    end
    return math.clamp((x - BOARD_X) // CELL + 1, 1, COLS)
end

## Whether a point is in the part of the screen that aims and drops a disc: the strip above the grid and the grid itself.
func inBoardZone(lay, x, y)
    return columnAt(x) <> nil and y >= lay.aimTop and y <= lay.panel.y + lay.panel.h
end

## The centre of a square, `row` counted from the bottom.
func cellX(col)
    return BOARD_X + (col - 1) * CELL + CELL / 2
end

func cellY(lay, row)
    return lay.boardY + (ROWS - 1 - row) * CELL + CELL / 2
end
