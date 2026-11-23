## What Connect Four looks like: the title, the grid with its discs and the one in the air, and what says whose move it is and how a game
## ended. It only reads the state.

import "state.ol"
import "layout.ol"

const BG       = Color(0.06, 0.08, 0.15)
const PANEL    = Color(0.13, 0.32, 0.82)
const PANEL_LO = Color(0.08, 0.2, 0.55)
const HOLE     = Color(0.05, 0.07, 0.13)
const RED      = Color(0.94, 0.23, 0.29)
const YELLOW   = Color(1.0, 0.83, 0.2)
const TEXT     = Color(0.95, 0.96, 1.0)
const DIM      = Color(0.64, 0.7, 0.86)
const KEY_FILL = Color(0.14, 0.18, 0.32)
const KEY_EDGE = Color(0.5, 0.58, 0.82)
const KEY_OFF  = Color(0.09, 0.11, 0.2)
const KEY_TEXT_OFF = Color(0.4, 0.44, 0.58)
const KEY_EDGE_OFF = Color(0.2, 0.24, 0.36)
const DISC_R   = CELL / 2 - 5

func discColour(player)
    if player == 1 then
        return RED
    end
    return YELLOW
end

func colourName(player)
    if player == 1 then
        return "red"
    end
    return "yellow"
end

## A text at x, y, in the anchor `h` ("left", "center" or "right"), its middle on y.
func label(str, x, y, size, col, h)
    gfx.push()
    gfx.fontSize(size)
    gfx.textMode(h, "center")
    gfx.stroke(col)
    gfx.text(str, x, y)
    gfx.pop()
end

func drawDisc(x, y, player, alpha)
    var c = discColour(player)
    gfx.noStroke()
    gfx.fill(Color(c.r, c.g, c.b, alpha))
    gfx.circle(x, y, DISC_R)
    gfx.noFill()
    gfx.stroke(Color(c.r * 0.72, c.g * 0.72, c.b * 0.72, alpha))
    gfx.strokeSize(3)
    gfx.circle(x, y, DISC_R - 7)
    gfx.noStroke()
end

## A button; `primary` is the one a screen wants pressed.
func drawButton(r, text, enabled, primary)
    var ink = TEXT
    gfx.strokeSize(2)
    if enabled and primary then
        gfx.fill(PANEL)
        gfx.stroke(TEXT)
    elseif enabled then
        gfx.fill(KEY_FILL)
        gfx.stroke(KEY_EDGE)
    else
        gfx.fill(KEY_OFF)
        gfx.stroke(KEY_EDGE_OFF)
        ink = KEY_TEXT_OFF
    end
    gfx.rect(r.x, r.y, r.w, r.h, 12)
    gfx.noStroke()
    label(text, r.x + r.w / 2, r.y + r.h / 2, 20, ink, "center")
end

## The grid: the blue panel, a hole for every square, and the discs in them.
func drawBoard(lay)
    var p = lay.panel
    gfx.noStroke()
    gfx.fill(PANEL_LO)
    gfx.rect(p.x, p.y + 4, p.w, p.h, 16)
    gfx.fill(PANEL)
    gfx.rect(p.x, p.y, p.w, p.h, 16)
    gfx.fill(HOLE)
    for col = 1, COLS do
        var x = cellX(col)
        for row = 0, ROWS - 1 do
            gfx.circle(x, cellY(lay, row), DISC_R)
        end
    end
    for col = 1, COLS do
        var x = cellX(col)
        for row = 0, heightOf(game, col) - 1 do
            if fall == nil or col <> fall.col or row <> fall.row then
                drawDisc(x, cellY(lay, row), cellAt(game, col, row), 1.0)
            end
        end
    end
    if fall <> nil then
        var e = math.min(fall.t / fall.dur, 1.0)
        var y = lay.aimY + (cellY(lay, fall.row) - lay.aimY) * e * e
        drawDisc(cellX(fall.col), y, fall.who, 1.0)
    end
    if outcome <> nil and fall == nil then
        var pulse = 0.55 + 0.45 * math.sin(elapsedTime * 7)
        gfx.noFill()
        gfx.stroke(Color(1, 1, 1, pulse))
        gfx.strokeSize(4)
        for c in outcome.cells do
            gfx.circle(cellX(c.col), cellY(lay, c.row), DISC_R + 1)
        end
        gfx.noStroke()
    end
end

## The disc held above the grid, and a faint band down the column it is aimed at.
func drawAim(lay)
    if not humansTurn() then
        return
    end
    gfx.noStroke()
    gfx.fill(Color(1, 1, 1, 0.07))
    gfx.rect(cellX(hover) - CELL / 2, lay.panel.y, CELL, lay.panel.h, 10)
    drawDisc(cellX(hover), lay.aimY, human, 0.85)
end

func dots()
    return ["", ".", "..", "..."][math.floor(elapsedTime * 3) % 4 + 1]
end

## What is said under the grid: whose move it is, or how the game ended.
func statusText()
    if state == "over" then
        if outcome.result == "draw" then
            return "A draw", TEXT
        elseif outcome.result == "win" then
            return "You win!", discColour(human)
        end
        return "The computer wins", discColour(computer)
    end
    if outcome <> nil then
        return "", TEXT                    ## the disc that ended the game is still falling
    end
    if toMove(game) == computer then
        return "Thinking" + dots(), DIM
    end
    return "Your move", discColour(human)
end

func drawPlay()
    var lay = playLay()
    label("Connect Four", VIEW_W / 2, lay.headerY + 24, 28, TEXT, "center")
    label("{levelName()} - you play {colourName(human)}", VIEW_W / 2, lay.headerY + 50, 15, DIM, "center")
    drawBoard(lay)
    drawAim(lay)
    var text, col = statusText()
    label(text, VIEW_W / 2, lay.statusY, 22, col, "center")
    if state == "over" then
        drawButton(lay.left, "Play again", true, true)
    else
        drawButton(lay.left, "Undo", canUndo(), false)
    end
    drawButton(lay.right, "Menu", true, false)
end

func drawTitle()
    var lay = titleLay()
    ## a row of discs for a logo
    for i = 1, COLS do
        drawDisc(cellX(i), lay.titleY - 54, 2 - i % 2, 1.0)
    end
    label("Connect Four", VIEW_W / 2, lay.titleY, 38, TEXT, "center")
    label("Four in a row against the computer", VIEW_W / 2, lay.subtitleY, 16, DIM, "center")
    for i, r in lay.levels do
        drawButton(r, LEVELS[i].name, true, i == levelIdx)
    end
    if humanFirst then
        drawButton(lay.first, "You play first", true, false)
    else
        drawButton(lay.first, "The computer plays first", true, false)
    end
    drawScores(lay.scores)
    if lay.cont <> nil then
        drawButton(lay.cont, "Continue ({#resumable.moves} discs)", true, true)
        drawButton(lay.start, "New game", true, false)
    else
        drawButton(lay.start, "Play", true, true)
    end
end

## The scores of the level the title shows.
func drawScores(r)
    var s = scores[levelIdx]
    gfx.noStroke()
    gfx.fill(KEY_OFF)
    gfx.rect(r.x, r.y, r.w, r.h, 12)
    var mid = r.x + r.w / 2
    label("{levelName()} level", mid, r.y + 22, 16, DIM, "center")
    label("Won {s.wins}    Lost {s.losses}    Drawn {s.draws}", mid, r.y + 54, 20, TEXT, "center")
    var fastest = "none yet"
    if s.fastest > 0 then
        fastest = "{s.fastest} moves"
    end
    label("Best run {s.bestStreak}    Fastest win: {fastest}", mid, r.y + 92, 15, DIM, "center")
end

func drawScreen()
    gfx.clear(BG)
    gfx.segments(24)                       ## the corners and the discs are small: the default 64 segments each would be thousands of triangles
    if state == "title" then
        drawTitle()
    else
        drawPlay()
    end
end
