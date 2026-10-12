## Blockudoku: a 9x9 grid cut into nine 3x3 boxes. Drag one of the three pieces onto the grid; every
## complete row, column or box is cleared. The game ends when none of the pieces left fits anywhere.
##
## board.ol holds the rules, pieces.ol the shapes, sounds.ol the sound; this file is the game: its
## state, its input, its animations and its drawing. The layout follows the orientation of the area
## (graphics.fitArea) and is computed again whenever it is needed, so nothing has to be kept in step.

import "board.ol"
import "pieces.ol"
import "sounds.ol"

const POINTS_PER_CELL = 1
const POINTS_PER_CLEARED_CELL = 10
const STREAK_BONUS = 50          ## per placement in a row that cleared something, after the first
const CLEAR_STAGGER = 0.025      ## seconds between two cells of the wave, per cell of distance
const CLEAR_TIME = 0.25
const LIFT_TOUCH = 1.7           ## cells between the finger and the bottom of the piece it holds
const LIFT_MOUSE = 0.6
const BEST_KEY = "blockudoku.best"

const PALETTE = [
    [0.93, 0.35, 0.35], [0.96, 0.60, 0.25], [0.96, 0.82, 0.30], [0.40, 0.80, 0.45],
    [0.30, 0.78, 0.80], [0.35, 0.55, 0.95], [0.65, 0.45, 0.90], [0.93, 0.50, 0.75]
]
const INK = [0.92, 0.94, 0.98, 1]
const MUTED = [0.55, 0.61, 0.74, 1]
const GOLD = [0.96, 0.82, 0.30, 1]

global grid = []
global cells = []            ## what is SHOWN per cell: colour, scale, flash — the grid holds the rules
global slots = []            ## the three pieces on offer; nil once placed
global state = "play"        ## play, clearing (an animation holds the input), over
global score = 0
global best = 0
global newBest = false
global streak = 0
global display = {score: 0, pop: 1}
global fade = {a: 0}
global held = nil
global heldSlot = nil
global dragId = nil
global target = {r: 0, c: 0, valid: false, near: false}
global previewCells = []
global clearSet = []
global clearPending = 0   ## cells of the wave still shrinking; the last one ends the turn
global L = {sx: [0, 0, 0], sy: [0, 0, 0]}
global layoutW = 0
global layoutH = 0

## ── Layout ──────────────────────────────────────────────────────────────────────────────────────

## The board and its trays in a column when the area is tall, side by side when it is wide: whichever
## gives the larger cell. It depends on W and H alone, so it is recomputed only when they change.
func layoutCompute()
    if W == layoutW and H == layoutH then
        return
    end
    layoutW = W
    layoutH = H
    var m = SIZE * 0.04
    var cp = math.min((W - 2 * m) / GRID, (H - 2 * m) / 15.2)
    var cl = math.min((H - 2 * m) / GRID, (W - 2 * m) / 14.3)
    var portrait = cp >= cl
    var c = math.floor(math.max(cp, cl))
    var bs = GRID * c
    L.c = c
    L.bs = bs
    if portrait then
        var top = (H - 15.2 * c) / 2
        L.bx = (W - bs) / 2
        L.by = top + 2.6 * c
        L.scoreX = L.bx
        L.scoreY = top
        L.bestX = L.bx + 3.5 * c
        L.bestY = top
        L.btnX = L.bx + 6.2 * c
        L.btnY = top + 0.3 * c
        L.btnW = 2.8 * c
        L.btnH = 1.6 * c
        L.tc = 0.55 * c
        L.sw = 1.5 * c
        L.sh = 1.6 * c
        for i = 1, 3 do
            L.sx[i] = L.bx + bs * (2 * i - 1) / 6
            L.sy[i] = L.by + bs + 2.0 * c
        end
    else
        var x0 = (W - (bs + 0.5 * c + 4.8 * c)) / 2
        var colX = x0 + bs + 0.5 * c
        L.bx = x0
        L.by = (H - bs) / 2
        L.scoreX = colX
        L.scoreY = L.by
        L.bestX = colX
        L.bestY = L.by + 1.6 * c
        L.btnX = colX + 2.5 * c
        L.btnY = L.by + 1.65 * c
        L.btnW = 2.3 * c
        L.btnH = 1.1 * c
        L.tc = 0.36 * c
        L.sw = 2.4 * c
        L.sh = 1.0 * c
        for i = 1, 3 do
            L.sx[i] = colX + 2.4 * c
            L.sy[i] = L.by + 3.0 * c + (i - 0.5) * 2.0 * c
        end
    end
    L.overW = 4.4 * c
    L.overH = 1.4 * c
    L.overX = L.bx + bs / 2 - L.overW / 2
    L.overY = L.by + 5.2 * c
end

func inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

## ── Game ────────────────────────────────────────────────────────────────────────────────────────

func newGame()
    tween.cancelAll()
    grid = boardNew()
    cells = []
    for i = 1, CELLS do
        cells.push({v: 0, s: 1, f: 0})
    end
    score = 0
    streak = 0
    newBest = false
    display.score = 0
    display.pop = 1
    fade.a = 0
    releaseHold()
    clearSet = []
    clearPending = 0
    state = "play"
    slots = []
    dealPieces()
end

func allSlotsEmpty()
    for i = 1, 3 do
        if slots[i] <> nil then
            return false
        end
    end
    return true
end

## Three pieces, redrawn until at least one of them fits: a hand that cannot be played at all ends
## the game on the spot, which is no fault of the player's.
func dealPieces()
    var picks = []
    for attempt = 1, 60 do
        picks = []
        for i = 1, 3 do
            picks.push(randomShape())
        end
        var playable = false
        for s in picks do
            if boardAnyMove(grid, s) then
                playable = true
            end
        end
        if playable then
            break
        end
    end
    layoutCompute()
    for i = 1, 3 do
        var p = {shape: picks[i], x: L.sx[i], y: H + 3 * L.c, size: L.tc, moving: true, lift: 0}
        slots[i] = p
        tween.to(p, {y: L.sy[i]}, 0.35, "easeOutBack", func()
            p.moving = false
        end).delay((i - 1) * 0.07)
    end
end

func isGameOver()
    for i = 1, 3 do
        if slots[i] <> nil and boardAnyMove(grid, slots[i].shape) then
            return false
        end
    end
    return true
end

func finishTurn()
    if allSlotsEmpty() then
        dealPieces()
    end
    if isGameOver() then
        gameOver()
    else
        state = "play"
    end
end

func gameOver()
    state = "over"
    tween.to(fade, {a: 1}, 0.5, "easeOutQuad")
    sndOver.play()
end

func showScore()
    display.pop = 1.3
    tween.to(display, {score: score}, 0.4, "easeOutQuad")
    tween.to(display, {pop: 1}, 0.3, "easeOutBack")
    if score > best then
        best = score
        newBest = true
        data.set(BEST_KEY, best)
    end
end

## The cells of the wave shrink one after the other, starting nearest to the piece just placed.
func animateClear(cleared, pr, pc)
    clearSet = cleared
    clearPending = len(cleared)
    for idx in cleared do
        var cell = cells[idx]
        var d = math.abs(boardRow(idx) - pr) + math.abs(boardCol(idx) - pc)
        cell.f = 1
        tween.to(cell, {s: 0, f: 0}, CLEAR_TIME, "easeInBack", func()
            clearPending -= 1
            if clearPending == 0 then
                finishClear()
            end
        end).delay(d * CLEAR_STAGGER)
    end
end

func finishClear()
    for idx in clearSet do
        var cell = cells[idx]
        cell.v = 0
        cell.s = 1
        cell.f = 0
    end
    clearSet = []
    finishTurn()
end

func placePiece(p, slot, r, c)
    boardPlace(grid, p.shape, r, c, p.shape.color)
    slots[slot] = nil
    score += p.shape.n * POINTS_PER_CELL
    var sumR = 0
    var sumC = 0
    for off in p.shape.cells do
        var rr = r + off[1]
        var cc = c + off[2]
        var cell = cells[boardIdx(rr, cc)]
        cell.v = p.shape.color
        cell.s = 1.2
        tween.to(cell, {s: 1}, 0.2, "easeOutQuad")
        sumR += rr
        sumC += cc
    end
    var cleared, zones = boardFull(grid)
    if zones > 0 then
        streak += 1
        score += zones * zones * GRID * POINTS_PER_CLEARED_CELL + (streak - 1) * STREAK_BONUS
        boardClear(grid, cleared)
        animateClear(cleared, sumR / p.shape.n, sumC / p.shape.n)
        sndClear[math.min(zones + streak - 1, len(sndClear))].play()
        state = "clearing"
        showScore()
    else
        streak = 0
        sndPlace.play()
        showScore()
        finishTurn()
    end
end

func returnPiece(p, slot)
    if target.near then
        sndBad.play()
    end
    p.moving = true
    tween.to(p, {x: L.sx[slot], y: L.sy[slot], size: L.tc}, 0.28, "easeOutCubic", func()
        p.moving = false
    end)
end

## ── Input ───────────────────────────────────────────────────────────────────────────────────────
## A single finger also emulates the mouse, so one gesture arrives twice. The first path to press owns
## the drag (dragId), and the other is ignored until it ends.

func slotAt(x, y)
    for i = 1, 3 do
        var p = slots[i]
        if p <> nil and not p.moving then
            if math.abs(x - L.sx[i]) <= L.sw and math.abs(y - L.sy[i]) <= L.sh then
                return i
            end
        end
    end
    return nil
end

## Where the held piece would land: the cell nearest its top-left corner, and whether it fits.
func updateTarget()
    var left = held.x - held.shape.w * L.c / 2
    var top = held.y - held.shape.h * L.c / 2
    target.c = math.round((left - L.bx) / L.c) + 1
    target.r = math.round((top - L.by) / L.c) + 1
    target.valid = boardCanPlace(grid, held.shape, target.r, target.c)
    target.near = false
    for off in held.shape.cells do
        var rr = target.r + off[1]
        var cc = target.c + off[2]
        if rr >= 1 and rr <= GRID and cc >= 1 and cc <= GRID then
            target.near = true
        end
    end
    previewCells = []
    if target.valid then
        previewCells = boardPreview(grid, held.shape, target.r, target.c)
    end
end

func moveHeld(x, y)
    held.x = x
    held.y = y - L.c * (held.lift + held.shape.h / 2)
    updateTarget()
end

func grab(id, slot, x, y)
    held = slots[slot]
    heldSlot = slot
    dragId = id
    ## A finger emulates the mouse, so the press may arrive as "mouse": the contacts say what it was.
    held.lift = LIFT_TOUCH
    if touch.count() == 0 then
        held.lift = LIFT_MOUSE
    end
    tween.to(held, {size: L.c}, 0.12, "easeOutQuad")
    moveHeld(x, y)
end

func pressAt(id, x, y)
    layoutCompute()
    if inRect(x, y, L.btnX, L.btnY, L.btnW, L.btnH) then
        newGame()
        return
    end
    if state == "over" then
        if inRect(x, y, L.overX, L.overY, L.overW, L.overH) then
            newGame()
        end
        return
    end
    if state <> "play" or dragId <> nil then
        return
    end
    var slot = slotAt(x, y)
    if slot <> nil then
        grab(id, slot, x, y)
    end
end

func moveTo(id, x, y)
    if dragId <> nil and id == dragId then
        layoutCompute()
        moveHeld(x, y)
    end
end

## The hold is over, whatever ended it: nothing is held, and no preview is shown.
func releaseHold()
    held = nil
    heldSlot = nil
    dragId = nil
    previewCells = []
end

func dropHeld()
    var p = held
    var slot = heldSlot
    releaseHold()
    if target.valid then
        placePiece(p, slot, target.r, target.c)
    else
        returnPiece(p, slot)
    end
end

func releaseAt(id, x, y)
    if dragId == nil or id <> dragId then
        return
    end
    layoutCompute()
    moveHeld(x, y)
    dropHeld()
end

func touch.began(id, x, y)
    pressAt(id, x, y)
end

func touch.moved(id, x, y)
    moveTo(id, x, y)
end

func touch.ended(id, x, y)
    releaseAt(id, x, y)
end

func mouse.pressed(x, y)
    pressAt("mouse", x, y)
end

func mouse.moved(x, y)
    moveTo("mouse", x, y)
end

func mouse.released(x, y)
    releaseAt("mouse", x, y)
end

## ── Drawing ─────────────────────────────────────────────────────────────────────────────────────

func drawText(str, x, y, size, h, v, col, alpha = 1)
    graphics.fontSize(size)
    graphics.textMode(h, v)
    graphics.stroke(col[1], col[2], col[3], col[4] * alpha)
    graphics.text(str, x, y)
    graphics.noStroke()
end

## The rectangle of a cell, inset to leave the gap between neighbours.
func cellRect(x, y, s)
    graphics.rect(x + s * 0.05, y + s * 0.05, s * 0.9, s * 0.9, s * 0.16)
end

func drawCell(x, y, s, color, alpha = 1)
    var col = PALETTE[color]
    var g = s * 0.05
    var inner = s - 2 * g
    graphics.noStroke()
    graphics.fill(col[1], col[2], col[3], alpha)
    graphics.rect(x + g, y + g, inner, inner, s * 0.18)
    graphics.fill(1, 1, 1, 0.22 * alpha)
    graphics.rect(x + g + s * 0.08, y + g + s * 0.06, inner - s * 0.16, inner * 0.32, s * 0.12)
end

func drawPiece(p, alpha = 1)
    var x0 = p.x - p.shape.w * p.size / 2
    var y0 = p.y - p.shape.h * p.size / 2
    for off in p.shape.cells do
        drawCell(x0 + off[2] * p.size, y0 + off[1] * p.size, p.size, p.shape.color, alpha)
    end
end

func drawHeader()
    var c = L.c
    drawText("SCORE", L.scoreX, L.scoreY, c * 0.36, "left", "top", MUTED)
    drawText("{math.round(display.score)}", L.scoreX, L.scoreY + c * 0.5, c * 0.95 * display.pop, "left", "top", INK)
    drawText("BEST", L.bestX, L.bestY, c * 0.36, "left", "top", MUTED)
    drawText("{best}", L.bestX, L.bestY + c * 0.5, c * 0.7, "left", "top", INK)
    graphics.noStroke()
    graphics.fill(0.22, 0.27, 0.40)
    graphics.rect(L.btnX, L.btnY, L.btnW, L.btnH, c * 0.3)
    drawText("New game", L.btnX + L.btnW / 2, L.btnY + L.btnH / 2, c * 0.42, "center", "center", INK)
end

func drawBoard()
    var c = L.c
    var pad = c * 0.18
    graphics.noStroke()
    graphics.fill(0.11, 0.13, 0.19)
    graphics.rect(L.bx - pad, L.by - pad, L.bs + 2 * pad, L.bs + 2 * pad, c * 0.3)
    for r = 1, GRID do
        for col = 1, GRID do
            var tint = ((r - 1) // BOX + (col - 1) // BOX) % 2
            graphics.fill(0.16 + 0.05 * tint, 0.19 + 0.05 * tint, 0.27 + 0.06 * tint)
            cellRect(L.bx + (col - 1) * c, L.by + (r - 1) * c, c)
        end
    end
    graphics.noFill()
    graphics.stroke(0.45, 0.52, 0.70, 0.7)
    graphics.strokeSize(c * 0.07)
    for k = 1, BOX - 1 do
        graphics.line(L.bx + k * BOX * c, L.by, L.bx + k * BOX * c, L.by + L.bs)
        graphics.line(L.bx, L.by + k * BOX * c, L.bx + L.bs, L.by + k * BOX * c)
    end
    for i = 1, CELLS do
        var cell = cells[i]
        if cell.v <> 0 and cell.s > 0.01 then
            var size = c * cell.s
            var x = L.bx + (boardCol(i) - 1) * c + (c - size) / 2
            var y = L.by + (boardRow(i) - 1) * c + (c - size) / 2
            drawCell(x, y, size, cell.v)
            if cell.f > 0.01 then
                graphics.fill(1, 1, 1, cell.f * 0.9)
                cellRect(x, y, size)
            end
        end
    end
end

## The shadow of the held piece where it would land, and the cells that landing would clear.
func drawPreview()
    if held == nil then
        return
    end
    var c = L.c
    for off in held.shape.cells do
        var rr = target.r + off[1]
        var cc = target.c + off[2]
        var x = L.bx + (cc - 1) * c
        var y = L.by + (rr - 1) * c
        if target.valid then
            drawCell(x, y, c, held.shape.color, 0.38)
        elseif rr >= 1 and rr <= GRID and cc >= 1 and cc <= GRID then
            graphics.noStroke()
            graphics.fill(0.95, 0.25, 0.25, 0.55)
            cellRect(x, y, c)
        end
    end
    for idx in previewCells do
        graphics.noStroke()
        graphics.fill(1, 1, 1, 0.28)
        cellRect(L.bx + (boardCol(idx) - 1) * c, L.by + (boardRow(idx) - 1) * c, c)
    end
end

func drawTrays()
    for i = 1, 3 do
        var p = slots[i]
        if p <> nil and p <> held then
            drawPiece(p)
        end
    end
end

func drawOver()
    if fade.a < 0.01 then
        return
    end
    var c = L.c
    graphics.noStroke()
    graphics.fill(0.03, 0.04, 0.08, 0.78 * fade.a)
    graphics.rect(0, 0, W, H)
    var mx = L.bx + L.bs / 2
    drawText("GAME OVER", mx, L.by + 2.3 * c, c * 1.1, "center", "center", INK, fade.a)
    drawText("Score {score}", mx, L.by + 3.6 * c, c * 0.7, "center", "center", INK, fade.a)
    if newBest then
        drawText("New best!", mx, L.by + 4.4 * c, c * 0.5, "center", "center", GOLD, fade.a)
    else
        drawText("Best {best}", mx, L.by + 4.4 * c, c * 0.5, "center", "center", MUTED, fade.a)
    end
    graphics.noStroke()
    graphics.fill(0.30, 0.55, 0.95, fade.a)
    graphics.rect(L.overX, L.overY, L.overW, L.overH, c * 0.3)
    drawText("New game", L.overX + L.overW / 2, L.overY + L.overH / 2, c * 0.55, "center", "center", INK, fade.a)
end

## ── Engine entry points ─────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Blockudoku")
    graphics.fitArea()
    buildShapes()
    buildSounds()
    best = data.get(BEST_KEY, 0)
    newGame()
end

## A piece waiting in its tray follows the tray, which moves when the area is turned or resized; one
## being animated is left to its tween, and the one held to the pointer.
func update()
    layoutCompute()
    for i = 1, 3 do
        var p = slots[i]
        if p <> nil and p <> held and not p.moving then
            p.x = L.sx[i]
            p.y = L.sy[i]
            p.size = L.tc
        end
    end
    ## A finger can vanish with no touch.ended (the browser cancelled it): the piece is dropped where it was.
    if dragId <> nil and dragId <> "mouse" and touch.count() == 0 then
        dropHeld()
    end
end

func draw()
    layoutCompute()
    graphics.clear(0.07, 0.08, 0.12)
    drawHeader()
    drawBoard()
    drawPreview()
    drawTrays()
    if held <> nil then
        var alpha = 0.96
        if target.near and not target.valid then
            alpha = 0.6        ## lets the red hint under the piece show through
        end
        drawPiece(held, alpha)
    end
    drawOver()
end
