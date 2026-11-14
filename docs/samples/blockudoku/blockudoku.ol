## Blockudoku: a 9x9 grid cut into nine 3x3 boxes. Drag one of the three pieces onto the grid; every complete row, column or box
## is cleared. The game ends when none of the pieces left fits anywhere.
##
## Two global objects hold everything: `config`, what can be tuned, and `game`, what changes as it runs; the other files keep
## theirs in one object each (`board`, `pieces`, `sounds`, `i18n`). The layout follows the orientation of the area
## (graphics.fitArea) and is computed again whenever it is needed, so nothing has to be kept in step.

import "board.ol"
import "pieces.ol"
import "deal.ol"
import "sounds.ol"
import "texts.ol"
import "../lib/draw.ol"
import "../lib/area.ol"
import "../lib/menu.ol"
import "layout.ol"
import "save.ol"
import "draw.ol"
import "screens.ol"

## What can be tuned: scores, durations, the keys of the saved data, the colours. Nothing here changes while
## the game runs.
global config = {
    pointsPerCell: 1,
    pointsPerClearedCell: 10,
    streakBonus: 50,            ## per placement in a row that cleared something, after the first
    clearStagger: 0.025,        ## seconds between two cells of the wave, per cell of distance
    clearTime: 0.25,
    liftTouch: 1.7,             ## cells between the finger and the bottom of the piece it holds
    liftMouse: 0.6,
    bestKey: "blockudoku.best",
    saveKey: "blockudoku.game",
    floatPop: 0.18,             ## seconds for a gained point to appear where it was earned
    floatHold: 0.12,            ## seconds it stays there before being drawn into the score
    floatFlight: 0.5,
    outline: [[-1, 0], [1, 0], [0, -1], [0, 1]],   ## where the dark copies of a point's text sit around it
    outlineInk: [0.04, 0.05, 0.09, 1],
    floatTint: [0.60, 0.75, 0.95, 1],   ## a gained point: light enough for its dark outline to read
    streakTint: [0.98, 0.85, 0.40, 1],
    blue: [0.22, 0.45, 0.85, 1],        ## the one colour of every block; the rules only make it lighter
    paper: 1,                           ## the background
    button: [0.22, 0.27, 0.40],         ## the fill of a button
    buttonPrimary: [0.30, 0.55, 0.95],  ## the one that matters on the end screen
    invalid: [0.95, 0.25, 0.25],        ## where a held piece cannot go
    ink: [0.13, 0.15, 0.21, 1],
    muted: [0.45, 0.49, 0.58, 1],
    gold: [0.80, 0.58, 0.05, 1],
    onButton: [1, 1, 1, 1],             ## the label of a button, whose fill is dark
    cellLight: 0.91,                    ## the empty cells, in two greys that alternate by 3x3 box
    cellDark: 0.83,
    menu: [                             ## the options screen, top to bottom: the key of its text, where it leads, and whether it is the main button
        {text: "menuHelp", goes: "help"},
        {text: "menuPieces", goes: "pieces"},
        {text: "menuLanguage", goes: "language"},
        {sound: true},                  ## shows the sound on or off, and a press switches it
        {text: "menuBack", goes: "game", primary: true}
    ],
    margin: 0.04,                       ## fractions of SIZE: the margin of a screen, the band its title takes, the margin of a text
    titleBand: 0.14,
    textMargin: 0.06,
    stuckLight: 0.62                    ## a piece that fits nowhere: the blue, washed out toward white, still within reach
}
config.floatLife = config.floatPop + config.floatHold + config.floatFlight
config.blueStuck = config.blue.map(func(v) return v + (1 - v) * config.stuckLight end)

## Everything that changes while the game runs.
global game = {
    grid: [],
    cells: [],                  ## what is SHOWN per cell: filled, scale, flash — the grid holds the rules
    slots: [],                  ## the three pieces on offer; nil once placed
    state: "play",              ## play, clearing (an animation holds the input), over
    score: 0,
    best: 0,
    newBest: false,
    streak: 0,
    display: {score: 0, pop: 1},   ## score: what the counter SHOWS, which catches up as each point lands
    floaters: [],               ## points gained, flying to the score: {row, col, text, tint, v, age}
    fade: {a: 0},
    held: nil,
    heldSlot: nil,
    dragId: nil,
    target: {r: 0, c: 0, valid: false, near: false},
    previewCells: [],
    layout: {w: 0, h: 0, sx: [0, 0, 0], sy: [0, 0, 0]},   ## where everything goes, computed again when W or H change
    screen: "game",             ## what is shown: the game, the options menu, the help, the languages or the catalogue of every piece
    screenTick: -1,             ## the tick of the last change of screen or of sound: the second path of the same gesture is ignored
    tick: 0,                    ## frames so far, which tells two gestures from one gesture that arrives twice
    sheet: {w: 0, h: 0, u: 0, ox: 0, oy: 0, items: []},   ## the catalogue's layout, computed again when W or H change
    help: {w: 0, h: 0, lang: "", x: 0, y: 0, size: 0, lines: []}   ## the help text cut into lines, computed again when W, H or the language change
}

## ── Game ────────────────────────────────────────────────────────────────────────────────────────

func newGame()
    resetGame()
    dealPieces()
end

func resetGame()
    tween.cancelAll()
    game.grid = boardNew()
    game.cells = []
    for i = 1, CELLS do
        game.cells.push({v: 0, s: 1, f: 0})
    end
    game.score = 0
    game.streak = 0
    game.newBest = false
    game.display.score = 0
    game.display.pop = 1
    game.floaters = []
    game.fade.a = 0
    releaseHold()
    game.state = "play"
    game.slots = []
end

## A piece on offer, in its tray (or on its way there when `moving`).
func newSlot(shape, x, y, moving)
    return {shape: shape, x: x, y: y, size: game.layout.tc, moving: moving, lift: 0, stuck: false}
end

func allSlotsEmpty()
    for i = 1, 3 do
        if game.slots[i] <> nil then
            return false
        end
    end
    return true
end

## Three pieces, drawn for the level the score has reached (see deal.ol).
func dealPieces()
    var L = game.layout
    var picks = drawHand(game.grid, levelOf(game.score))
    layoutCompute()
    for i = 1, 3 do
        var p = newSlot(picks[i], L.sx[i], H + 3 * L.c, true)
        game.slots[i] = p
        tween.to(p, {y: L.sy[i]}, 0.35, "easeOutBack", func()
            p.moving = false
        end).delay((i - 1) * 0.07)
    end
    refreshStuck()
    saveGame()
end

## Marks the pieces on offer that fit nowhere on the grid. Called whenever the grid or the hand changes,
## not every frame: the search walks the whole board.
func refreshStuck()
    for i = 1, 3 do
        if game.slots[i] <> nil then
            game.slots[i].stuck = not boardAnyMove(game.grid, game.slots[i].shape)
        end
    end
end

## Reads the marks of refreshStuck, so it is only right once the hand is settled.
func isGameOver()
    for i = 1, 3 do
        if game.slots[i] <> nil and not game.slots[i].stuck then
            return false
        end
    end
    return true
end

## A new hand when the last piece is placed, and every piece marked: the hand is up to date for the game.
func settleHand()
    if allSlotsEmpty() then
        dealPieces()
    else
        refreshStuck()
    end
end

func finishTurn()
    settleHand()
    if isGameOver() then
        gameOver()
    else
        game.state = "play"
    end
end

func gameOver()
    game.state = "over"
    tween.to(game.fade, {a: 1}, 0.5, "easeOutQuad")
    sounds.over.play()
end

func updateBest()
    if game.score > game.best then
        game.best = game.score
        game.newBest = true
        data.set(config.bestKey, game.best)
    end
end

## A gained point shows where it was earned (row and col are in cells, fractions allowed), then is drawn
## into the score, shrinking: the counter only grows when it lands, so it never runs ahead of what is seen.
## Its progress is computed from its age rather than tweened, so there is no callback to outlive it.
func spawnFloater(row, col, v, tint, delay)
    game.floaters.push({row: row, col: col, text: "+{v}", tint: tint, v: v, age: -delay})
end

func updateFloaters()
    if len(game.floaters) == 0 then
        return
    end
    var flying = []
    for f in game.floaters do
        f.age += deltaTime
        if f.age < config.floatLife then
            flying.push(f)
        else
            game.display.score += f.v
            game.display.pop = 1.18
            tween.to(game.display, {pop: 1}, 0.18, "easeOutQuad")
        end
    end
    game.floaters = flying
end

## The cells of the wave shrink one after the other, starting nearest to the piece just placed.
func animateClear(cleared, pr, pc, bonus, placed)
    var pending = len(cleared)      ## cells of the wave still shrinking; the last one ends the turn
    var share = bonus // len(cleared)
    var extra = bonus % len(cleared)      ## the first cells carry one more, so the shares add up exactly
    for n, idx in cleared do
        var cell = game.cells[idx]
        var d = math.abs(boardRow(idx) - pr) + math.abs(boardCol(idx) - pc)
        var v = share
        if n <= extra then
            v += 1
        end
        if placed[idx] then
            v += config.pointsPerCell      ## one cell carries one point, not two
        end
        spawnFloater(boardRow(idx), boardCol(idx), v, config.floatTint, d * config.clearStagger)
        cell.f = 1
        tween.to(cell, {s: 0, f: 0}, config.clearTime, "easeInBack", func()
            cell.v = 0
            cell.s = 1
            cell.f = 0
            pending -= 1
            if pending == 0 then
                finishTurn()
            end
        end).delay(d * config.clearStagger)
    end
end

func placePiece(p, slot, r, c)
    boardPlace(game.grid, p.shape, r, c)
    game.slots[slot] = nil
    game.score += p.shape.n * config.pointsPerCell
    var sumR = 0
    var sumC = 0
    var placed = {}
    for off in p.shape.cells do
        var rr = r + off[1]
        var cc = c + off[2]
        var cell = game.cells[boardIdx(rr, cc)]
        cell.v = 1
        cell.s = 1.2
        tween.to(cell, {s: 1}, 0.2, "easeOutQuad")
        placed[boardIdx(rr, cc)] = true
        sumR += rr
        sumC += cc
    end
    var pr = sumR / p.shape.n        ## the centre of the piece: where the wave starts and the streak bonus is born
    var pc = sumC / p.shape.n
    var cleared, zones = boardFull(game.grid)
    boardClear(game.grid, cleared)
    var n = 0
    for off in p.shape.cells do
        if game.grid[boardIdx(r + off[1], c + off[2])] <> 0 then
            spawnFloater(r + off[1], c + off[2], config.pointsPerCell, config.floatTint, n * 0.03)
            n += 1
        end
    end
    if zones > 0 then
        game.streak += 1
        var bonus = zones * zones * GRID * config.pointsPerClearedCell
        var streakBonus = (game.streak - 1) * config.streakBonus
        game.score += bonus + streakBonus
        animateClear(cleared, pr, pc, bonus, placed)
        if streakBonus > 0 then
            spawnFloater(pr, pc, streakBonus, config.streakTint, 0.1)
        end
        playClear(zones, game.streak)
        game.state = "clearing"
    else
        game.streak = 0
        sounds.place.play()
        finishTurn()
    end
    updateBest()
    saveGame()
end

func returnPiece(p, slot)
    var L = game.layout
    if game.target.near then
        sounds.bad.play()
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
    var L = game.layout
    for i = 1, 3 do
        var p = game.slots[i]
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
    var L = game.layout
    var held = game.held
    var t = game.target
    var left = held.x - held.shape.w * L.c / 2
    var top = held.y - held.shape.h * L.c / 2
    var c = math.round((left - L.bx) / L.c) + 1
    var r = math.round((top - L.by) / L.c) + 1
    if c == t.c and r == t.r and held.shape == t.shape then
        return
    end
    t.c = c
    t.r = r
    t.shape = held.shape
    t.valid = boardCanPlace(game.grid, held.shape, r, c)
    t.near = false
    for off in held.shape.cells do
        if boardInside(r + off[1], c + off[2]) then
            t.near = true
        end
    end
    if t.valid then
        game.previewCells = boardPreview(game.grid, held.shape, r, c)
    else
        game.previewCells = []
    end
end

func moveHeld(x, y)
    var L = game.layout
    game.held.x = x
    game.held.y = y - L.c * (game.held.lift + game.held.shape.h / 2)
    updateTarget()
end

func grab(id, slot, x, y)
    var L = game.layout
    game.held = game.slots[slot]
    game.heldSlot = slot
    game.dragId = id
    game.target.shape = nil          ## the grid may have changed since the last drag: nothing is remembered
    ## A finger emulates the mouse, so the press may arrive as "mouse": the contacts say what it was.
    game.held.lift = config.liftTouch
    if touch.count() == 0 then
        game.held.lift = config.liftMouse
    end
    tween.to(game.held, {size: L.c}, 0.12, "easeOutQuad")
    moveHeld(x, y)
end

func pressAt(id, x, y)
    var L = game.layout
    if game.tick == game.screenTick then
        return
    end
    if game.screen <> "game" then
        screens[game.screen].press(x, y)
        return
    end
    layoutCompute()
    if inRect(x, y, L.gear) then
        if game.dragId == nil then
            showScreen("options")
        end
        return
    end
    if inRect(x, y, L.newBtn) then
        newGame()
        return
    end
    if game.state == "over" then
        if inRect(x, y, L.over) then
            newGame()
        end
        return
    end
    if game.state <> "play" or game.dragId <> nil then
        return
    end
    var slot = slotAt(x, y)
    if slot <> nil then
        grab(id, slot, x, y)
    end
end

func moveTo(id, x, y)
    if game.dragId <> nil and id == game.dragId then
        layoutCompute()
        moveHeld(x, y)
    end
end

## The hold is over, whatever ended it: nothing is held, so no preview is drawn.
func releaseHold()
    game.held = nil
    game.heldSlot = nil
    game.dragId = nil
end

func dropHeld()
    var p = game.held
    var slot = game.heldSlot
    releaseHold()
    if game.target.valid then
        placePiece(p, slot, game.target.r, game.target.c)
    else
        returnPiece(p, slot)
    end
end

func releaseAt(id, x, y)
    if game.dragId == nil or id <> game.dragId then
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

## ── Engine entry points ─────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Blockudoku")
    graphics.fitArea()
    buildShapes()
    buildSounds()
    restoreLanguage()
    useMenu({ink: config.ink, button: config.button, primary: config.buttonPrimary, accent: config.blue, paper: config.paper,
             margin: config.margin, width: 0.7, height: 0.11, soundKey: "blockudoku.sound",
             drawButton: drawButton, showScreen: showScreen})
    game.best = data.get(config.bestKey, 0)
    if not loadGame() then
        newGame()
    end
end

## A piece waiting in its tray follows the tray, which moves when the area is turned or resized; one
## being animated is left to its tween, and the one held to the pointer.
func update()
    var L = game.layout
    game.tick += 1
    layoutCompute()
    for i = 1, 3 do
        var p = game.slots[i]
        if p <> nil and p <> game.held and not p.moving then
            p.x = L.sx[i]
            p.y = L.sy[i]
            p.size = L.tc
        end
    end
    updateFloaters()
    ## A finger can vanish with no touch.ended (the browser cancelled it): the piece is dropped where it was.
    if game.dragId <> nil and game.dragId <> "mouse" and touch.count() == 0 then
        dropHeld()
    end
end

func draw()
    layoutCompute()
    graphics.clear(config.paper)
    graphics.noStroke()
    if game.screen <> "game" then
        screens[game.screen].draw()
        return
    end
    drawHeader()
    drawBoard()
    drawPreview()
    drawTrays()
    if game.held <> nil then
        var alpha = 0.96
        if game.target.near and not game.target.valid then
            alpha = 0.6        ## lets the red hint under the piece show through
        end
        drawPiece(game.held, alpha)
    end
    drawFloaters()
    drawOver()
end
