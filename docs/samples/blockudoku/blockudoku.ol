## Blockudoku: a 9x9 grid cut into nine 3x3 boxes. Drag one of the three pieces onto the grid; every
## complete row, column or box is cleared. The game ends when none of the pieces left fits anywhere.
##
## board.ol holds the rules, pieces.ol the shapes, sounds.ol the sound; this file is the game: its
## state, its input, its animations and its drawing. The layout follows the orientation of the area
## (graphics.fitArea) and is computed again whenever it is needed, so nothing has to be kept in step.
##
## Two global objects hold everything: `config`, what can be tuned, and `game`, what changes as it runs.
## The other files keep theirs in one object each: `board`, `pieces`, `sounds`.

import "board.ol"
import "pieces.ol"
import "sounds.ol"

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
    blue: [0.22, 0.45, 0.85],           ## the one colour of every block; the rules only make it lighter
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
    menu: [                             ## the options screen, top to bottom: a label, where the entry leads, and whether it is the main button
        {label: "How to play", goes: "help"},
        {label: "All pieces", goes: "pieces"},
        {label: "Back to game", goes: "game", primary: true}
    ],
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
    screen: "game",             ## what is shown: the game, the options menu, the help or the catalogue of every piece
    screenTick: -1,             ## the tick of the last change: the second path of the same gesture is ignored
    tick: 0,                    ## frames so far, which tells two gestures from one gesture that arrives twice
    sheet: {w: 0, h: 0, u: 0, ox: 0, oy: 0, items: []},   ## the catalogue's layout, computed again when W or H change
    help: {w: 0, h: 0, x: 0, y: 0, size: 0, lines: []}    ## the help text cut into lines, computed again when W or H change
}

## ── Layout ──────────────────────────────────────────────────────────────────────────────────────

## True when W or H differ from the area `cache` was computed for, which it then remembers: what depends on the
## area alone is computed again only then.
func areaChanged(cache)
    if W == cache.w and H == cache.h then
        return false
    end
    cache.w = W
    cache.h = H
    return true
end

## The board and its trays in a column when the area is tall, side by side when it is wide: whichever
## gives the larger cell. It depends on W and H alone, so it is recomputed only when they change.
func layoutCompute()
    var L = game.layout
    if not areaChanged(L) then
        return
    end
    var m = SIZE * 0.04
    var colH = 15.2                 ## the height of the column of the header, the board and the trays, in cells
    var cp = math.min((W - 2 * m) / GRID, (H - 2 * m) / colH)
    var cl = math.min((H - 2 * m) / GRID, (W - 2 * m) / 14.3)
    var portrait = cp >= cl
    var c = math.floor(math.max(cp, cl))
    var gear = math.max(SIZE * 0.08, 40)
    L.gearS = gear
    L.gearX = W - m - gear
    L.gearY = m
    if portrait then
        ## The header must not run under the gear: a narrow and short area shrinks the board until it clears.
        while c > 8 and (W + GRID * c) / 2 > L.gearX - 0.3 * m and (H - colH * c) / 2 < L.gearY + gear + 0.3 * m do
            c -= 1
        end
    end
    var bs = GRID * c
    L.c = c
    L.bs = bs
    if portrait then
        var top = (H - colH * c) / 2
        L.bx = (W - bs) / 2
        L.by = top + 2.6 * c
        L.scoreX = L.bx
        L.scoreY = top
        L.bestX = L.bx + 3.5 * c
        L.bestY = top
        L.btnX = L.bx + 6.2 * c
        L.btnY = top
        L.btnW = 2.8 * c
        L.btnH = 1.1 * c
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

## The catalogue: every shape the game can deal, as large as the screen lets them be.
func sheetCompute()
    if not areaChanged(game.sheet) then
        return
    end
    var m = SIZE * 0.04
    var top = SIZE * 0.14
    var areaW = W - 2 * m
    var areaH = H - top - m
    var u = math.floor(areaW / 5)
    var items, used = packShapes(u, areaW)
    while used > areaH and u > 4 do
        u -= 1
        items, used = packShapes(u, areaW)
    end
    game.sheet.u = u
    game.sheet.ox = m
    game.sheet.oy = top + (areaH - used) / 2
    game.sheet.items = items
end

## What the help says, one string per paragraph. The figures come from config, so the text cannot drift from the rules.
func helpParagraphs()
    return [
        "Drag one of the three pieces onto the grid and let go to place it. A piece cannot be turned.",
        "Fill a whole row, a whole column or a whole {BOX}x{BOX} box and it is cleared. Several at once are cleared together.",
        "Each cell you place scores {config.pointsPerCell}. Each zone you clear scores {GRID * config.pointsPerClearedCell}, and clearing several zones at once multiplies that by their number.",
        "Clear something on consecutive turns and you build a streak: each turn of the streak adds {config.streakBonus} more points than the one before.",
        "A faded piece fits nowhere on the grid right now. The game is over when none of the three pieces can be placed.",
        "Your game is saved as you play, and your best score is kept."
    ]
end

## The help cut into lines no wider than areaW, with the font size already set: a blank line ends each paragraph.
func wrapHelp(size, areaW)
    graphics.fontSize(size)
    var lines = []
    for text in helpParagraphs() do
        var line = ""
        for word in text.split(" ") do
            var tryLine = word
            if line <> "" then
                tryLine = line + " " + word
            end
            var tw = graphics.textSize(tryLine)
            if tw > areaW and line <> "" then
                lines.push(line)
                line = word
            else
                line = tryLine
            end
        end
        lines.push(line)
        lines.push("")
    end
    return lines
end

## The help at the largest size that fits under the title.
func helpCompute()
    var help = game.help
    if not areaChanged(help) then
        return
    end
    var m = SIZE * 0.06
    var areaW = W - 2 * m
    var areaH = H - SIZE * 0.14 - m
    var size = math.floor(SIZE * 0.04)
    var lines = wrapHelp(size, areaW)
    while len(lines) * size * 1.35 > areaH and size > 10 do
        size -= 1
        lines = wrapHelp(size, areaW)
    end
    help.x = m
    help.y = SIZE * 0.14
    help.size = size
    help.lines = lines
end

func showScreen(name)
    assert(name == "game" or screens[name] <> nil, "unknown screen")
    game.screen = name
    game.screenTick = game.tick
end

## The rectangle of the i-th entry of the options menu, centred in the area.
func optionRect(i)
    var w = math.min(W - 2 * SIZE * 0.04, SIZE * 0.7)
    var h = SIZE * 0.11
    var gap = h * 0.35
    var top = H / 2 - (len(config.menu) * h + (len(config.menu) - 1) * gap) / 2
    return CX - w / 2, top + (i - 1) * (h + gap), w, h
end

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

## The game in progress, as one text: score, streak, the 81 cells (a digit each, 0 for empty), and the
## shape of each of the three pieces ("-" once placed). Written after every move, so closing the page
## loses nothing; loadGame refuses a game that was already lost.
func saveGame()
    var keys = []
    for i = 1, 3 do
        if game.slots[i] == nil then
            keys.push("-")
        else
            keys.push(game.slots[i].shape.key)
        end
    end
    data.set(config.saveKey, "{game.score}|{game.streak}|{game.grid.join()}|{keys.join(",")}")
end

## A piece on offer, in its tray (or on its way there when `moving`).
func newSlot(shape, x, y, moving)
    return {shape: shape, x: x, y: y, size: game.layout.tc, moving: moving, lift: 0, stuck: false}
end

## Puts a saved game back; false (and nothing resumed) when there is none, when it does not read, or when it
## was already lost. Every part is checked before anything is touched.
func loadGame()
    var L = game.layout
    var saved = data.get(config.saveKey)
    if saved == nil then
        return false
    end
    var parts = saved.split("|")
    if len(parts) <> 4 then
        return false
    end
    var savedScore = parts[1].number()
    var savedStreak = parts[2].number()
    var keys = parts[4].split(",")
    if savedScore == nil or savedStreak == nil or len(parts[3]) <> CELLS or len(keys) <> 3 then
        return false
    end
    var g = boardNew()
    for i = 1, CELLS do
        var v = parts[3].char(i).number()
        if v == nil or v < 0 then
            return false
        end
        g[i] = math.min(v, 1)
    end
    var picks = []
    for key in keys do
        if key == "-" then
            picks.push(nil)
        else
            var shape = shapeFromKey(key)
            if shape == nil then
                return false
            end
            picks.push(shape)
        end
    end
    resetGame()
    game.grid = g
    game.score = savedScore
    game.streak = savedStreak
    game.display.score = game.score
    for i = 1, CELLS do
        game.cells[i].v = game.grid[i]
    end
    layoutCompute()
    for i = 1, 3 do
        if picks[i] == nil then
            game.slots[i] = nil
        else
            game.slots[i] = newSlot(picks[i], L.sx[i], L.sy[i], false)
        end
    end
    settleHand()
    return not isGameOver()
end

func allSlotsEmpty()
    for i = 1, 3 do
        if game.slots[i] <> nil then
            return false
        end
    end
    return true
end

## Three pieces, redrawn until at least one of them fits: a hand that cannot be played at all ends
## the game on the spot, which is no fault of the player's.
func dealPieces()
    var L = game.layout
    var picks = []
    for attempt = 1, 60 do
        picks = []
        for i = 1, 3 do
            picks.push(randomShape())
        end
        var playable = false
        for s in picks do
            if boardAnyMove(game.grid, s) then
                playable = true
                break
            end
        end
        if playable then
            break
        end
    end
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
        animateClear(cleared, sumR / p.shape.n, sumC / p.shape.n, bonus, placed)
        if streakBonus > 0 then
            spawnFloater(sumR / p.shape.n, sumC / p.shape.n, streakBonus, config.streakTint, 0.1)
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
    var left = game.held.x - game.held.shape.w * L.c / 2
    var top = game.held.y - game.held.shape.h * L.c / 2
    var c = math.round((left - L.bx) / L.c) + 1
    var r = math.round((top - L.by) / L.c) + 1
    if c == game.target.c and r == game.target.r and game.held.shape == game.target.shape then
        return
    end
    game.target.c = c
    game.target.r = r
    game.target.shape = game.held.shape
    game.target.valid = boardCanPlace(game.grid, game.held.shape, game.target.r, game.target.c)
    game.target.near = false
    for off in game.held.shape.cells do
        var rr = game.target.r + off[1]
        var cc = game.target.c + off[2]
        if boardInside(rr, cc) then
            game.target.near = true
        end
    end
    game.previewCells = []
    if game.target.valid then
        game.previewCells = boardPreview(game.grid, game.held.shape, game.target.r, game.target.c)
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
    if inRect(x, y, L.gearX, L.gearY, L.gearS, L.gearS) then
        if game.dragId == nil then
            showScreen("options")
        end
        return
    end
    if inRect(x, y, L.btnX, L.btnY, L.btnW, L.btnH) then
        newGame()
        return
    end
    if game.state == "over" then
        if inRect(x, y, L.overX, L.overY, L.overW, L.overH) then
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

## A block: the one blue, or the washed-out one of a piece that fits nowhere.
func drawCell(x, y, s, alpha = 1, stuck = false)
    var col = config.blue
    if stuck then
        col = config.blueStuck
    end
    var g = s * 0.05
    var inner = s - 2 * g
    graphics.noStroke()
    graphics.fill(col[1], col[2], col[3], alpha)
    graphics.rect(x + g, y + g, inner, inner, s * 0.18)
    graphics.fill(1, 1, 1, 0.22 * alpha)
    graphics.rect(x + g + s * 0.08, y + g + s * 0.06, inner - s * 0.16, inner * 0.32, s * 0.12)
end

func drawPiece(p, alpha = 1, stuck = false)
    var x0 = p.x - p.shape.w * p.size / 2
    var y0 = p.y - p.shape.h * p.size / 2
    for off in p.shape.cells do
        drawCell(x0 + off[2] * p.size, y0 + off[1] * p.size, p.size, alpha, stuck)
    end
end

func drawButton(label, x, y, w, h, fill, textSize, alpha = 1)
    var L = game.layout
    graphics.noStroke()
    graphics.fill(fill[1], fill[2], fill[3], alpha)
    graphics.rect(x, y, w, h, L.c * 0.3)
    drawText(label, x + w / 2, y + h / 2, textSize, "center", "center", config.onButton, alpha)
end

## The button of the options screen: a toothed wheel with a hole, on the fill of the other buttons.
func drawGear(x, y, s)
    graphics.noStroke()
    graphics.fill(config.button[1], config.button[2], config.button[3])
    graphics.rect(x, y, s, s, s * 0.22)
    graphics.fill(config.onButton[1], config.onButton[2], config.onButton[3])
    graphics.push()
    graphics.translate(x + s / 2, y + s / 2)
    graphics.rectMode("center")
    for k = 1, 8 do
        graphics.rect(0, -s * 0.30, s * 0.13, s * 0.15)
        graphics.rotate(45)
    end
    graphics.pop()
    graphics.circle(x + s / 2, y + s / 2, s * 0.24)
    graphics.fill(config.button[1], config.button[2], config.button[3])
    graphics.circle(x + s / 2, y + s / 2, s * 0.10)
end

func drawHeader()
    var L = game.layout
    var c = L.c
    drawText("SCORE", L.scoreX, L.scoreY, c * 0.36, "left", "top", config.muted)
    drawText("{math.round(game.display.score)}", L.scoreX, L.scoreY + c * 0.5, c * 0.95 * game.display.pop, "left", "top", config.ink)
    drawText("BEST", L.bestX, L.bestY, c * 0.36, "left", "top", config.muted)
    drawText("{game.best}", L.bestX, L.bestY + c * 0.5, c * 0.7, "left", "top", config.ink)
    drawButton("New game", L.btnX, L.btnY, L.btnW, L.btnH, config.button, c * 0.42)
    drawGear(L.gearX, L.gearY, L.gearS)
end

## The points in flight: each grows where it was earned, then flies to the score, smaller as it goes.
func drawFloaters()
    var L = game.layout
    var c = L.c
    var tx = L.scoreX + c * 0.6
    var ty = L.scoreY + c * 1.0
    for f in game.floaters do
        if f.age > 0 then
            var u = math.min(f.age / config.floatPop, 1) - 1
            var grow = 1 + 2.70158 * u * u * u + 1.70158 * u * u          ## easeOutBack
            var q = math.clamp((f.age - config.floatPop - config.floatHold) / config.floatFlight, 0, 1)
            var k = q * q                                                  ## easeInQuad: it picks up speed
            var x0 = L.bx + (f.col - 0.5) * c
            var y0 = L.by + (f.row - 0.5) * c
            var x = x0 + (tx - x0) * k
            var y = y0 + (ty - y0) * k
            var size = c * 0.46 * grow * (1 - 0.75 * k)
            var alpha = 1 - math.max(0, (k - 0.8) / 0.2)
            var edge = size * 0.07
            for off in config.outline do
                drawText(f.text, x + off[1] * edge, y + off[2] * edge, size, "center", "center", config.outlineInk, alpha * 0.9)
            end
            drawText(f.text, x, y, size, "center", "center", f.tint, alpha)
        end
    end
end

func drawBoard()
    var L = game.layout
    var c = L.c
    graphics.noStroke()
    for r = 1, GRID do
        for col = 1, GRID do
            var tint = ((r - 1) // BOX + (col - 1) // BOX) % 2
            var grey = config.cellLight - (config.cellLight - config.cellDark) * tint
            graphics.fill(grey)
            cellRect(L.bx + (col - 1) * c, L.by + (r - 1) * c, c)
        end
    end
    var i = 0
    for r = 1, GRID do
        for col = 1, GRID do
            i += 1
            var cell = game.cells[i]
            if cell.v <> 0 and cell.s > 0.01 then
                var size = c * cell.s
                var x = L.bx + (col - 1) * c + (c - size) / 2
                var y = L.by + (r - 1) * c + (c - size) / 2
                drawCell(x, y, size)
                if cell.f > 0.01 then
                    graphics.fill(1, 1, 1, cell.f * 0.9)
                    cellRect(x, y, size)
                end
            end
        end
    end
end

## The shadow of the held piece where it would land, and the cells that landing would clear.
func drawPreview()
    var L = game.layout
    if game.held == nil then
        return
    end
    var c = L.c
    for off in game.held.shape.cells do
        var rr = game.target.r + off[1]
        var cc = game.target.c + off[2]
        var x = L.bx + (cc - 1) * c
        var y = L.by + (rr - 1) * c
        if game.target.valid then
            drawCell(x, y, c, 0.38)
        elseif boardInside(rr, cc) then
            graphics.noStroke()
            graphics.fill(config.invalid[1], config.invalid[2], config.invalid[3], 0.55)
            cellRect(x, y, c)
        end
    end
    for idx in game.previewCells do
        graphics.noStroke()
        graphics.fill(1, 1, 1, 0.5)
        cellRect(L.bx + (boardCol(idx) - 1) * c, L.by + (boardRow(idx) - 1) * c, c)
    end
end

func drawTrays()
    for i = 1, 3 do
        var p = game.slots[i]
        if p <> nil and p <> game.held then
            drawPiece(p, 1, p.stuck)
        end
    end
end

func drawOver()
    var L = game.layout
    if game.fade.a < 0.01 then
        return
    end
    var c = L.c
    graphics.noStroke()
    graphics.fill(config.paper, 0.85 * game.fade.a)
    graphics.rect(0, 0, W, H)
    var mx = L.bx + L.bs / 2
    drawText("GAME OVER", mx, L.by + 2.3 * c, c * 1.1, "center", "center", config.ink, game.fade.a)
    drawText("Score {game.score}", mx, L.by + 3.6 * c, c * 0.7, "center", "center", config.ink, game.fade.a)
    if game.newBest then
        drawText("New best!", mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.gold, game.fade.a)
    else
        drawText("Best {game.best}", mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.muted, game.fade.a)
    end
    drawButton("New game", L.overX, L.overY, L.overW, L.overH, config.buttonPrimary, c * 0.55, game.fade.a)
end

## The title of a screen that replaces the game: the background is already painted.
func drawScreenTitle(title)
    drawText(title, CX, SIZE * 0.06, SIZE * 0.05, "center", "center", config.ink)
end

## The options menu: one button per entry of config.menu.
func drawOptions()
    drawScreenTitle("OPTIONS")
    for i, entry in config.menu do
        var x, y, w, h = optionRect(i)
        var fill = config.button
        if entry.primary then
            fill = config.buttonPrimary
        end
        drawButton(entry.label, x, y, w, h, fill, h * 0.4)
    end
end

## A press on the options menu: the entry under it, if any.
func pressOptions(x, y)
    for i, entry in config.menu do
        var rx, ry, rw, rh = optionRect(i)
        if inRect(x, y, rx, ry, rw, rh) then
            showScreen(entry.goes)
            return
        end
    end
end

func backToOptions(x, y)
    showScreen("options")
end

func drawHelp()
    helpCompute()
    var help = game.help
    drawScreenTitle("HOW TO PLAY")
    var y = help.y
    for line in help.lines do
        if line <> "" then
            drawText(line, help.x, y, help.size, "left", "top", config.ink)
        end
        y += help.size * 1.35
    end
    drawText("tap anywhere to go back", CX, H - SIZE * 0.04, SIZE * 0.027, "center", "center", config.muted)
end

func drawGallery()
    sheetCompute()
    drawScreenTitle("ALL PIECES")
    drawText("{len(pieces.shapes)} shapes, tap anywhere to go back", CX, SIZE * 0.11, SIZE * 0.027, "center", "center", config.muted)
    var u = game.sheet.u
    for item in game.sheet.items do
        var s = item.shape
        for off in s.cells do
            drawCell(game.sheet.ox + item.x + off[2] * u, game.sheet.oy + item.y + off[1] * u, u)
        end
    end
end

## The screens that replace the game, by name: how each is drawn and what a press on it does.
global screens = {
    options: {draw: drawOptions, press: pressOptions},
    help: {draw: drawHelp, press: backToOptions},
    pieces: {draw: drawGallery, press: backToOptions}
}

## ── Engine entry points ─────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Blockudoku")
    graphics.fitArea()
    buildShapes()
    buildSounds()
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
