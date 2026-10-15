## Blockudoku: a 9x9 grid cut into nine 3x3 boxes. Drag one of the three pieces onto the grid; every
## complete row, column or box is cleared. The game ends when none of the pieces left fits anywhere.
##
## board.ol holds the rules, pieces.ol the shapes, sounds.ol the sound, texts.ol the words in French and
## English; this file is the game: its state, its input, its animations and its drawing. The layout follows
## the orientation of the area (graphics.fitArea) and is computed again whenever it is needed, so nothing
## has to be kept in step.
##
## Two global objects hold everything: `config`, what can be tuned, and `game`, what changes as it runs.
## The other files keep theirs in one object each: `board`, `pieces`, `sounds`, `i18n`.

import "board.ol"
import "pieces.ol"
import "sounds.ol"
import "texts.ol"

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
    langKey: "blockudoku.lang",
    soundKey: "blockudoku.sound",
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
    screenTick: -1,             ## the tick of the last change: the second path of the same gesture is ignored
    tick: 0,                    ## frames so far, which tells two gestures from one gesture that arrives twice
    sheet: {w: 0, h: 0, u: 0, ox: 0, oy: 0, items: []},   ## the catalogue's layout, computed again when W or H change
    help: {w: 0, h: 0, lang: "", x: 0, y: 0, size: 0, lines: []}   ## the help text cut into lines, computed again when W, H or the language change
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
    var m = SIZE * config.margin
    ## What the area must hold, in cells: the height of the column (header, board, trays) when it stands, and the width
    ## of the board plus its side column when they stand together. They add up the offsets placed below.
    var colH = 15.2
    var rowW = 14.3
    var cp = math.min((W - 2 * m) / GRID, (H - 2 * m) / colH)
    var cl = math.min((H - 2 * m) / GRID, (W - 2 * m) / rowW)
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
        L.tc = 0.36 * c
        L.sw = 2.4 * c
        L.sh = 1.0 * c
        for i = 1, 3 do
            L.sx[i] = colX + 2.4 * c
            L.sy[i] = L.by + 3.0 * c + (i - 0.5) * 2.0 * c
        end
    end
    L.btnH = 1.1 * c
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
    var m = SIZE * config.margin
    var top = SIZE * config.titleBand
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

## What the help says, one string per paragraph, in the current language. The figures come from config, so the text
## cannot drift from the rules.
func helpParagraphs()
    return tr("help")({box: BOX, cell: config.pointsPerCell, zone: GRID * config.pointsPerClearedCell, streak: config.streakBonus})
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
    if not areaChanged(help) and help.lang == i18n.lang then
        return
    end
    help.lang = i18n.lang
    var m = SIZE * config.textMargin
    var top = SIZE * config.titleBand
    var areaW = W - 2 * m
    var areaH = H - top - m
    var size = math.floor(SIZE * 0.04)
    var lines = wrapHelp(size, areaW)
    while len(lines) * size * 1.35 > areaH and size > 10 do
        size -= 1
        lines = wrapHelp(size, areaW)
    end
    help.x = m
    help.y = top
    help.size = size
    help.lines = lines
end

func showScreen(name)
    assert(name == "game" or screens[name] <> nil, "unknown screen")
    game.screen = name
    game.screenTick = game.tick
end

## The rectangle of the i-th of n entries of a menu, centred in the area.
func optionRect(i, n)
    var w = math.min(W - 2 * SIZE * config.margin, SIZE * 0.7)
    var h = SIZE * 0.11
    var gap = h * 0.35
    var top = H / 2 - (n * h + (n - 1) * gap) / 2
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

## The top-left corner on the screen of the cell at row r, column c.
func cellOrigin(r, c)
    var L = game.layout
    return L.bx + (c - 1) * L.c, L.by + (r - 1) * L.c
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
    graphics.fill(col[1], col[2], col[3], alpha)
    graphics.rect(x + g, y + g, inner, inner, s * 0.18)
    graphics.fill(1, 1, 1, 0.22 * alpha)
    graphics.rect(x + g + s * 0.08, y + g + s * 0.06, inner - s * 0.16, inner * 0.32, s * 0.12)
end

## The blocks of a shape whose top-left corner is at (x0, y0), s wide each.
func drawShape(shape, x0, y0, s, alpha = 1, stuck = false)
    for off in shape.cells do
        drawCell(x0 + off[2] * s, y0 + off[1] * s, s, alpha, stuck)
    end
end

func drawPiece(p, alpha = 1, stuck = false)
    drawShape(p.shape, p.x - p.shape.w * p.size / 2, p.y - p.shape.h * p.size / 2, p.size, alpha, stuck)
end

## The size at which the text is no wider than maxW, `size` at most: a translation is not as long as the original.
func fitSize(str, size, maxW)
    graphics.fontSize(size)
    var tw = graphics.textSize(str)
    if tw > maxW then
        return size * maxW / tw
    end
    return size
end

func drawButton(label, x, y, w, h, fill, textSize, alpha = 1)
    var L = game.layout
    graphics.fill(fill[1], fill[2], fill[3], alpha)
    graphics.rect(x, y, w, h, L.c * 0.3)
    drawText(label, x + w / 2, y + h / 2, fitSize(label, textSize, w * 0.9), "center", "center", config.onButton, alpha)
end

## The button of the options screen: a thick toothed wheel in the blue of the blocks, with a hole through to the paper.
func drawGear(x, y, s)
    graphics.fill(config.blue[1], config.blue[2], config.blue[3])
    graphics.push()
    graphics.translate(x + s / 2, y + s / 2)
    graphics.rectMode("center")
    for k = 1, 8 do
        graphics.rect(0, -s * 0.34, s * 0.20, s * 0.20, s * 0.04)
        graphics.rotate(45)
    end
    graphics.pop()
    graphics.circle(x + s / 2, y + s / 2, s * 0.30)
    graphics.fill(config.paper)
    graphics.circle(x + s / 2, y + s / 2, s * 0.13)
end

func drawHeader()
    var L = game.layout
    var c = L.c
    drawText(tr("score").upper(), L.scoreX, L.scoreY, c * 0.36, "left", "top", config.muted)
    drawText("{math.round(game.display.score)}", L.scoreX, L.scoreY + c * 0.5, c * 0.95 * game.display.pop, "left", "top", config.ink)
    drawText(tr("best").upper(), L.bestX, L.bestY, c * 0.36, "left", "top", config.muted)
    drawText("{game.best}", L.bestX, L.bestY + c * 0.5, c * 0.7, "left", "top", config.ink)
    drawButton(tr("newGame"), L.btnX, L.btnY, L.btnW, L.btnH, config.button, c * 0.42)
    drawGear(L.gearX, L.gearY, L.gearS)
end

## The points in flight: each grows where it was earned, then flies to the score, smaller as it goes.
func drawFloaters()
    var L = game.layout
    var c = L.c
    var tx = L.scoreX + c * 0.6
    var ty = L.scoreY + c * 1.0
    var ink = config.outlineInk
    graphics.textMode("center", "center")
    for f in game.floaters do
        if f.age > 0 then
            var u = math.min(f.age / config.floatPop, 1) - 1
            var grow = 1 + 2.70158 * u * u * u + 1.70158 * u * u          ## easeOutBack
            var q = math.clamp((f.age - config.floatPop - config.floatHold) / config.floatFlight, 0, 1)
            var k = q * q                                                  ## easeInQuad: it picks up speed
            var ox, oy = cellOrigin(f.row, f.col)
            var x0 = ox + c / 2
            var y0 = oy + c / 2
            var x = x0 + (tx - x0) * k
            var y = y0 + (ty - y0) * k
            var size = c * 0.46 * grow * (1 - 0.75 * k)
            var alpha = 1 - math.max(0, (k - 0.8) / 0.2)
            var edge = size * 0.07
            graphics.fontSize(size)
            graphics.stroke(ink[1], ink[2], ink[3], ink[4] * alpha * 0.9)
            for off in config.outline do
                graphics.text(f.text, x + off[1] * edge, y + off[2] * edge)
            end
            graphics.stroke(f.tint[1], f.tint[2], f.tint[3], f.tint[4] * alpha)
            graphics.text(f.text, x, y)
        end
    end
    graphics.noStroke()
end

func drawBoard()
    var L = game.layout
    var c = L.c
    ## The empty cells, the two greys of the 3x3 boxes one after the other: a fill per grey, not per cell.
    for tint = 0, 1 do
        graphics.fill(config.cellLight - (config.cellLight - config.cellDark) * tint)
        for r = 1, GRID do
            for col = 1, GRID do
                if ((r - 1) // BOX + (col - 1) // BOX) % 2 == tint then
                    var x, y = cellOrigin(r, col)
                    cellRect(x, y, c)
                end
            end
        end
    end
    for r = 1, GRID do
        for col = 1, GRID do
            var cell = game.cells[boardIdx(r, col)]
            if cell.v <> 0 and cell.s > 0.01 then
                var size = c * cell.s
                var ox, oy = cellOrigin(r, col)
                var x = ox + (c - size) / 2
                var y = oy + (c - size) / 2
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
    var held = game.held
    if held == nil then
        return
    end
    var c = L.c
    var t = game.target
    if t.valid then
        var x0, y0 = cellOrigin(t.r, t.c)
        drawShape(held.shape, x0, y0, c, 0.38)
    else
        graphics.fill(config.invalid[1], config.invalid[2], config.invalid[3], 0.55)
        for off in held.shape.cells do
            if boardInside(t.r + off[1], t.c + off[2]) then
                var x, y = cellOrigin(t.r + off[1], t.c + off[2])
                cellRect(x, y, c)
            end
        end
    end
    graphics.fill(1, 1, 1, 0.5)
    for idx in game.previewCells do
        var x, y = cellOrigin(boardRow(idx), boardCol(idx))
        cellRect(x, y, c)
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
    graphics.fill(config.paper, 0.85 * game.fade.a)
    graphics.rect(0, 0, W, H)
    var mx = L.bx + L.bs / 2
    drawText(tr("gameOver"), mx, L.by + 2.3 * c, fitSize(tr("gameOver"), c * 1.1, L.bs * 0.95), "center", "center", config.ink, game.fade.a)
    drawText("{tr("score")} {game.score}", mx, L.by + 3.6 * c, c * 0.7, "center", "center", config.ink, game.fade.a)
    if game.newBest then
        drawText(tr("newBest"), mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.gold, game.fade.a)
    else
        drawText("{tr("best")} {game.best}", mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.muted, game.fade.a)
    end
    drawButton(tr("newGame"), L.overX, L.overY, L.overW, L.overH, config.buttonPrimary, c * 0.55, game.fade.a)
end

## The title of a screen that replaces the game: the background is already painted.
func drawScreenTitle(title)
    drawText(title.upper(), CX, SIZE * 0.06, SIZE * 0.05, "center", "center", config.ink)
end

## The buttons of a menu screen, top to bottom: {label, primary, and what a press does: lead somewhere (goes), pick a language (lang) or switch the sound}.
func optionEntries()
    var entries = []
    for entry in config.menu do
        var key = entry.text
        if entry.sound then
            key = sounds.on and "menuSoundOn" or "menuSoundOff"
        end
        entries.push({label: tr(key), goes: entry.goes, sound: entry.sound, primary: entry.primary})
    end
    return entries
end

func languageEntries()
    var entries = []
    for code in LANGUAGES do
        entries.push({label: TEXTS[code].name, lang: code, primary: code == i18n.lang})
    end
    entries.push({label: tr("back"), goes: "options"})
    return entries
end

func drawEntries(entries)
    for i, entry in entries do
        var x, y, w, h = optionRect(i, len(entries))
        var fill = config.button
        if entry.primary then
            fill = config.buttonPrimary
        end
        drawButton(entry.label, x, y, w, h, fill, h * 0.4)
    end
end

## Picks a language and keeps it for the next launch.
func chooseLanguage(code)
    setLanguage(code)
    data.set(config.langKey, code)
end

## Switches the sound and keeps the choice for the next launch.
func toggleSound()
    setSound(not sounds.on)
    data.set(config.soundKey, sounds.on)
end

## A press on a menu: the entry under it, if any.
func pressEntries(entries, x, y)
    for i, entry in entries do
        var rx, ry, rw, rh = optionRect(i, len(entries))
        if inRect(x, y, rx, ry, rw, rh) then
            if entry.lang <> nil then
                chooseLanguage(entry.lang)
            elseif entry.sound then
                toggleSound()
            else
                showScreen(entry.goes)
            end
            return
        end
    end
end

## A screen made of a menu: its title, and the entries that make its buttons.
func menuScreen(titleKey, entries)
    return {
        draw: func()
            drawScreenTitle(tr(titleKey))
            drawEntries(entries())
        end,
        press: func(x, y)
            pressEntries(entries(), x, y)
        end
    }
end

func backToOptions(x, y)
    showScreen("options")
end

func drawHelp()
    helpCompute()
    var help = game.help
    drawScreenTitle(tr("menuHelp"))
    var y = help.y
    for line in help.lines do
        if line <> "" then
            drawText(line, help.x, y, help.size, "left", "top", config.ink)
        end
        y += help.size * 1.35
    end
    drawText(tr("tapBack"), CX, H - SIZE * 0.04, SIZE * 0.027, "center", "center", config.muted)
end

func drawGallery()
    sheetCompute()
    drawScreenTitle(tr("menuPieces"))
    drawText("{len(pieces.shapes)} {tr("shapes")}, {tr("tapBack")}", CX, SIZE * 0.11, SIZE * 0.027, "center", "center", config.muted)
    var sheet = game.sheet
    for item in sheet.items do
        drawShape(item.shape, sheet.ox + item.x, sheet.oy + item.y, sheet.u)
    end
end

## The screens that replace the game, by name: how each is drawn and what a press on it does.
global screens = {
    options: menuScreen("options", optionEntries),
    help: {draw: drawHelp, press: backToOptions},
    pieces: {draw: drawGallery, press: backToOptions},
    language: menuScreen("menuLanguage", languageEntries)
}

## ── Engine entry points ─────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Blockudoku")
    graphics.fitArea()
    buildShapes()
    buildSounds()
    setLanguage(data.get(config.langKey, i18n.lang))
    setSound(data.get(config.soundKey, true))
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
