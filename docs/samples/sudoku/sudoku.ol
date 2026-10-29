## Sudoku: fill the 9x9 grid so that every row, column and 3x3 box holds the digits 1 to 9 once. Tap a cell, then a
## digit; the pencil notes the digits a cell could hold; a hint circles a cell and says how to find its digit.
##
## board.ol holds the rules, solver.ol the solver and the logic that grades a puzzle and gives the hints,
## generator.ol the puzzles, sounds.ol the sound, texts.ol the words in French and English; this file is the game: its
## state, its input, its animations and its drawing. The layout follows the orientation of the area (graphics.fitArea)
## and is computed again whenever it is needed, so nothing has to be kept in step.
##
## Two global objects hold everything: `config`, what can be tuned, and `game`, what changes as it runs.

import "board.ol"
import "solver.ol"
import "generator.ol"
import "sounds.ol"
import "texts.ol"
import "../lib/draw.ol"

const HINTS = 3                      ## hints per puzzle

global config = {
    saveKey: "sudoku.game",
    langKey: "sudoku.lang",
    soundKey: "sudoku.sound",
    errorsKey: "sudoku.errors",
    inputKey: "sudoku.input",
    dailyKey: "sudoku.daily",
    margin: 0.04,                    ## fractions of SIZE: the margin of a screen, the band its title takes, the margin of a text
    textMargin: 0.06,
    stepSeconds: 0.012,              ## the processor time a puzzle is worked on per frame while it is generated
    popTime: 0.2,
    winTime: 1.6,
    paper: 1,                        ## the background
    ink: [0.13, 0.15, 0.21, 1],      ## the digits of the puzzle
    muted: [0.45, 0.49, 0.58, 1],
    blue: [0.20, 0.42, 0.85, 1],     ## the digits the player placed
    red: [0.86, 0.16, 0.16, 1],      ## a digit in conflict
    amber: [0.97, 0.62, 0.08, 1],    ## the circle of a hint
    boxLight: [1, 1, 1, 1],          ## the nine boxes alternate between two tints
    boxDark: [0.94, 0.95, 0.97, 1],
    peerTint: [0.86, 0.91, 1.0, 1],  ## the row, column and box of the selected cell
    sameTint: [0.74, 0.84, 1.0, 1],  ## the cells that hold the digit of the selected one
    selectTint: [0.58, 0.74, 1.0, 1],
    conflictTint: [1.0, 0.82, 0.82, 1],
    hintTint: [1.0, 0.94, 0.72, 1],  ## the unit a hidden-single hint talks about
    thin: [0.74, 0.77, 0.84, 1],
    button: [0.22, 0.27, 0.40, 1],
    buttonOn: [0.30, 0.55, 0.95, 1],
    buttonOff: [0.78, 0.80, 0.86, 1],
    onButton: [1, 1, 1, 1],
    gold: [1.0, 0.82, 0.25, 1],
    pad: [0.90, 0.92, 0.97, 1],      ## a digit key of the pad
    padDone: [0.96, 0.97, 0.98, 1]
}

## Everything that changes while the game runs.
global game = {
    puzzle: [],                      ## the clues
    grid: [],                        ## the clues and what the player placed
    solution: [],
    notes: [],                       ## a mask of pencilled digits per cell
    undo: [],                        ## every move made, to take back
    conflicts: [],                   ## 1 for each cell in conflict, refreshed when the grid changes
    selected: 0,                     ## the cell being worked on, 0 for none
    armed: 0,                        ## the digit picked in the digit-then-cells input, 0 for none
    pencil: false,
    level: 1,
    daily: nil,                      ## {year, month, day} for the puzzle of the day
    hints: HINTS,
    hint: nil,                       ## the hint on show: {kind, cell, digit, unit}
    message: "",                     ## the line under the grid
    errors: true,                    ## whether a conflict shows in red
    input: "cell",                   ## "cell" (a cell, then a digit) or "digit" (a digit, then cells)
    state: "play",                   ## play, won
    screen: "play",                  ## what is shown: the game, or a menu, the help, the choice of a level, the wait
    job: nil,                        ## the puzzle being generated: the generator's job, plus the day it is for
    tick: 0,                         ## frames so far, which tells two gestures from one gesture that arrives twice
    pressTick: -1,
    pop: {cell: 0, s: 1},            ## the cell that grows a little when a digit is placed in it
    win: {t: 0, cell: 0},            ## the wave over the grid when it is solved
    help: {key: "", size: 0, lines: []},   ## the wrapped help, see helpLayout
    done: {},                        ## the puzzles of the day solved: "20261019:2" -> true
    layout: {w: 0, h: 0, c: 0, bx: 0, by: 0, pad: [], tools: []}
}

## ── Layout ──────────────────────────────────────────────────────────────────────────────────────

func rectOf(x, y, w, h)
    return {x: x, y: y, w: w, h: h}
end

func inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

## The grid and its controls in a column when the area is tall, side by side when it is wide: whichever gives the
## cells the room. Computed again only when W or H change.
func layoutCompute()
    var L = game.layout
    if W == L.w and H == L.h then
        return
    end
    L.w = W
    L.h = H
    var m = SIZE * config.margin
    var colH = 15.6
    var rowW = 15.0
    var cp = math.min((W - 2 * m) / N, (H - 2 * m) / colH)
    var cl = math.min((W - 2 * m) / rowW, (H - 2 * m) / N)
    var portrait = cp >= cl
    var c = math.floor(math.max(cp, cl))
    L.c = c
    L.bs = N * c
    L.pad = []
    L.tools = []
    if portrait then
        var top = (H - colH * c) / 2
        L.bx = (W - L.bs) / 2
        L.by = top + 1.9 * c
        L.titleX = L.bx
        L.titleY = top
        L.gear = rectOf(L.bx + L.bs - 1.3 * c, top + 0.1 * c, 1.3 * c, 1.3 * c)
        L.newBtn = rectOf(L.gear.x - 0.3 * c - 3.6 * c, top + 0.1 * c, 3.6 * c, 1.3 * c)
        L.msg = rectOf(L.bx, L.by + L.bs + 0.25 * c, L.bs, 1.3 * c)
        var y0 = L.by + L.bs + 1.75 * c
        for d = 1, N do
            L.pad.push(rectOf(L.bx + (d - 1) * c + 0.04 * c, y0, 0.92 * c, 1.3 * c))
        end
        var tw = (L.bs - 3 * 0.2 * c) / 4
        for k = 1, 4 do
            L.tools.push(rectOf(L.bx + (k - 1) * (tw + 0.2 * c), y0 + 1.65 * c, tw, 1.2 * c))
        end
    else
        var x0 = (W - rowW * c) / 2
        L.bx = x0
        L.by = (H - L.bs) / 2
        var rx = x0 + 9.6 * c
        var rw = 5.4 * c
        L.titleX = rx
        L.titleY = L.by
        L.gear = rectOf(rx + rw - 1.2 * c, L.by, 1.2 * c, 1.2 * c)
        L.newBtn = rectOf(rx, L.by + 1.5 * c, rw, 1.1 * c)
        L.msg = rectOf(rx, L.by + 2.8 * c, rw, 1.6 * c)
        var kw = (rw - 2 * 0.15 * c) / 3
        for d = 1, N do
            var col = (d - 1) % 3
            var row = (d - 1) // 3
            L.pad.push(rectOf(rx + col * (kw + 0.15 * c), L.by + 4.6 * c + row * (0.95 * c + 0.12 * c), kw, 0.95 * c))
        end
        var tw = (rw - 3 * 0.1 * c) / 4
        for k = 1, 4 do
            L.tools.push(rectOf(rx + (k - 1) * (tw + 0.1 * c), L.by + 7.9 * c, tw, 1.1 * c))
        end
    end
end

## The top-left corner of a cell on the screen.
func cellPos(i)
    var L = game.layout
    return L.bx + (board.colOf[i] - 1) * L.c, L.by + (board.rowOf[i] - 1) * L.c
end

## The cell under a point, or 0.
func cellAt(x, y)
    var L = game.layout
    if x < L.bx or y < L.by or x >= L.bx + L.bs or y >= L.by + L.bs then
        return 0
    end
    return boardIdx(math.floor((y - L.by) / L.c) + 1, math.floor((x - L.bx) / L.c) + 1)
end

func showScreen(name)
    game.screen = name
end

## The rectangle of the i-th of n entries of a menu, centred in the area.
func optionRect(i, n)
    var w = math.min(W - 2 * SIZE * config.margin, SIZE * 0.8)
    var h = math.min(SIZE * 0.1, (H * 0.84) / (n * 1.35))
    var gap = h * 0.35
    var top = H / 2 - (n * h + (n - 1) * gap) / 2
    return rectOf(CX - w / 2, top + (i - 1) * (h + gap), w, h)
end

## ── The game ────────────────────────────────────────────────────────────────────────────────────

func levelName(level)
    return tr(["levelEasy", "levelMedium", "levelHard", "levelExpert"][level])
end

func dailyKey(date, level)
    return "{dayNumber(date.year, date.month, date.day)}:{level}"
end

func today()
    var d = date.now()
    return {year: d.year, month: d.month, day: d.day}
end

func randomSeed()
    return (math.floor(time() * 1000) + math.randInt(1, 1000000)) % 2147483646 + 1
end

func refreshConflicts()
    game.conflicts = boardConflicts(game.grid)
end

func clearHint()
    game.hint = nil
    game.message = ""
end

## Puts a generated puzzle in play.
func installPuzzle(made, level, daily)
    tween.cancelAll()
    game.puzzle = boardCopy(made.puzzle)
    game.grid = boardCopy(made.puzzle)
    game.solution = made.solution
    game.notes = notesNew()
    game.undo = []
    game.level = level
    game.daily = daily
    game.hints = HINTS
    game.selected = 0
    game.armed = 0
    game.pencil = false
    game.pop.cell = 0
    game.win.t = 0
    clearHint()
    refreshConflicts()
    game.state = "play"
    game.screen = "play"
end

## A new puzzle of a level, or the one of a day: the work is done a little each frame, with a wait screen.
func startGame(level, daily)
    var seed = randomSeed()
    if daily <> nil then
        seed = dailySeed(daily.year, daily.month, daily.day, level)
    end
    game.job = generatorNew(seed, level)
    game.job.daily = daily
    showScreen("generating")
    sounds.confirm.play()
end

func updateGenerating()
    if game.job <> nil and generatorStep(game.job, config.stepSeconds) then
        var job = game.job
        game.job = nil
        installPuzzle(job.result, job.level, job.daily)
        saveGame()
    end
end

## A move is kept before it is made, with every note, so that undoing it puts everything back.
func pushUndo(i)
    game.undo.push({cell: i, value: game.grid[i], notes: boardCopy(game.notes)})
end

func undoMove()
    if game.state <> "play" or len(game.undo) == 0 then
        return
    end
    var e = game.undo.pop()
    game.grid[e.cell] = e.value
    game.notes = e.notes
    game.selected = e.cell
    clearHint()
    refreshConflicts()
    sounds.erase.play()
    saveGame()
end

## Whether the row, the column or the box of cell i is now full and right.
func unitDone(i)
    for u in [board.rowOf[i], N + board.colOf[i], 2 * N + board.boxOf[i]] do
        var seen = 0
        for j in board.units[u] do
            if game.grid[j] == 0 then
                return false
            end
            seen = seen | (1 << game.grid[j])
        end
        if seen == ALL then
            return true
        end
    end
    return false
end

func win(i)
    game.state = "won"
    game.selected = 0
    game.win.cell = i
    game.win.t = 0
    tween.to(game.win, {t: 1}, config.winTime, "easeOutQuad")
    for k, note in sounds.win do
        var t = {v: 0}
        tween.to(t, {v: 1}, 0.01, "linear", func()
            note.play()
        end).delay(k * 0.09)
    end
    if game.daily <> nil then
        game.done[dailyKey(game.daily, game.level)] = true
        saveDone()
    end
    data.set(config.saveKey, "")
end

## What changed in cell i, which now holds d (0 when it was emptied).
func afterChange(i, d)
    refreshConflicts()
    clearHint()
    game.pop.cell = i
    game.pop.s = 1.25
    tween.to(game.pop, {s: 1}, config.popTime, "easeOutQuad")
    if d == 0 then
        sounds.erase.play()
    elseif game.errors and game.conflicts[i] <> 0 then
        sounds.bad.play()
    elseif unitDone(i) then
        sounds.unit.play()
    else
        sounds.place.play()
    end
    if boardComplete(game.grid) then
        win(i)
    else
        saveGame()
    end
end

## A digit for a cell: a note in pencil mode, otherwise the digit, which a second time takes away.
func enterDigit(i, d)
    if game.state <> "play" or game.puzzle[i] <> 0 then
        return
    end
    if game.pencil and game.grid[i] <> 0 then
        return
    end
    pushUndo(i)
    if game.pencil then
        notesToggle(game.notes, i, d)
        clearHint()
        sounds.place.play()
        saveGame()
        return
    end
    if game.grid[i] == d then
        game.grid[i] = 0
        afterChange(i, 0)
        return
    end
    game.grid[i] = d
    game.notes[i] = 0
    notesClean(game.notes, i, d)
    afterChange(i, d)
end

func eraseSelected()
    var i = game.selected
    if game.state <> "play" or i == 0 or game.puzzle[i] <> 0 then
        return
    end
    if game.grid[i] == 0 and game.notes[i] == 0 then
        return
    end
    pushUndo(i)
    game.grid[i] = 0
    game.notes[i] = 0
    afterChange(i, 0)
end

## A hint: a wrong digit is shown for nothing; otherwise one of the hints of the puzzle is spent.
func askHint()
    if game.state <> "play" then
        return
    end
    var h = hintFor(game.grid, game.solution)
    if h.kind <> "mistake" then
        if game.hints <= 0 then
            game.hint = nil
            game.message = tr("hintNone")
            return
        end
        game.hints -= 1
        saveGame()
    end
    game.hint = h
    game.selected = h.cell
    game.message = hintText(h)
    sounds.confirm.play()
end

func togglePencil()
    game.pencil = not game.pencil
    sounds.confirm.play()
end

func selectCell(i)
    game.selected = i
    if game.hint <> nil and game.hint.cell <> i then
        clearHint()
    end
end

## A tap on a digit of the pad.
func pressDigit(d)
    if game.state <> "play" then
        return
    end
    if game.input == "digit" then
        if game.armed == d then
            game.armed = 0
        else
            game.armed = d
        end
        return
    end
    if game.selected <> 0 then
        enterDigit(game.selected, d)
    end
end

## A tap on a cell.
func pressCell(i)
    if game.state <> "play" then
        return
    end
    selectCell(i)
    if game.input == "digit" and game.armed <> 0 then
        enterDigit(i, game.armed)
    end
end

## ── Saved data ──────────────────────────────────────────────────────────────────────────────────

func saveGame()
    if game.state <> "play" then
        return
    end
    data.set(config.saveKey, gameEncode(game.puzzle, game.grid, game.notes, game.hints, game.level, game.daily))
end

func saveDone()
    data.set(config.dailyKey, game.done.keys().join(","))
end

func loadDone()
    game.done = {}
    var text = data.get(config.dailyKey, "")
    if typeof(text) == "string" and text <> "" then
        for k in text.split(",") do
            game.done[k] = true
        end
    end
end

## Puts a saved game back; false (and nothing resumed) when there is none, when it does not read, when its puzzle has
## not one solution, or when it was already solved. Every part is checked before anything is touched.
func loadGame()
    var saved = gameDecode(data.get(config.saveKey), HINTS, 4)
    if saved == nil then
        return false
    end
    var found = solverCount(saved.puzzle, 2, nil)
    if found.count <> 1 or boardComplete(saved.grid) then
        return false
    end
    installPuzzle({puzzle: saved.puzzle, solution: found.solution}, saved.level, saved.daily)
    game.grid = saved.grid
    game.notes = saved.notes
    game.hints = saved.hints
    refreshConflicts()
    return true
end

## ── Settings ────────────────────────────────────────────────────────────────────────────────────

func chooseLanguage(code)
    setLanguage(code)
    data.set(config.langKey, code)
end

## A tap arrives twice in the same frame (touch, then the mouse the system emulates from it), and a switch is the
## one press that is not idempotent: press() ignores the second path of the same gesture.
func toggleSound()
    setSound(not sounds.on)
    data.set(config.soundKey, sounds.on)
    if sounds.on then
        sounds.confirm.play()
    end
end

func toggleErrors()
    game.errors = not game.errors
    data.set(config.errorsKey, game.errors)
end

func toggleInput()
    if game.input == "cell" then
        game.input = "digit"
    else
        game.input = "cell"
    end
    game.armed = 0
    data.set(config.inputKey, game.input)
end

## ── Drawing ─────────────────────────────────────────────────────────────────────────────────────

func drawButton(label, r, fill, textSize, ink = nil)
    var L = game.layout
    if ink == nil then
        ink = config.onButton
    end
    fillC(fill)
    graphics.rect(r.x, r.y, r.w, r.h, L.c * 0.28)
    drawText(label, r.x + r.w / 2, r.y + r.h / 2, fitSize(label, textSize, r.w * 0.88), "center", "center", ink)
end

## The button of the options screen: a thick toothed wheel, with a hole through to the paper.
func drawGear(r)
    var s = r.w
    fillC(config.blue)
    graphics.push()
    graphics.translate(r.x + s / 2, r.y + s / 2)
    graphics.rectMode("center")
    for k = 1, 8 do
        graphics.rect(0, -s * 0.34, s * 0.20, s * 0.20, s * 0.04)
        graphics.rotate(45)
    end
    graphics.pop()
    graphics.circle(r.x + s / 2, r.y + s / 2, s * 0.30)
    graphics.fill(config.paper)
    graphics.circle(r.x + s / 2, r.y + s / 2, s * 0.13)
end

func drawHeader()
    var L = game.layout
    var c = L.c
    var label = tr("level").upper()
    if game.daily <> nil then
        label = tr("daily").upper()
    end
    drawText(label, L.titleX, L.titleY + 0.05 * c, c * 0.36, "left", "top", config.muted)
    drawText(levelName(game.level), L.titleX, L.titleY + 0.55 * c, fitSize(levelName(game.level), c * 0.95, c * 4.2), "left", "top", config.ink)
    drawButton(tr("newGame"), L.newBtn, config.button, c * 0.42)
    drawGear(L.gear)
end

func drawBoard()
    var L = game.layout
    var c = L.c
    var sel = game.selected
    var digit = game.armed
    if digit == 0 and sel <> 0 then
        digit = game.grid[sel]
    end
    var peerCells = {}
    if sel <> 0 then
        for j in board.peers[sel] do
            peerCells[j] = true
        end
    end
    var hintCells = {}
    if game.hint <> nil and game.hint.kind == "hidden" then
        for j in board.units[game.hint.unit] do
            hintCells[j] = true
        end
    end
    graphics.noStroke()
    for i = 1, CELLS do
        var x, y = cellPos(i)
        var tint = config.boxLight
        if ((board.boxOf[i] - 1) // BOX + (board.boxOf[i] - 1) % BOX) % 2 == 1 then
            tint = config.boxDark
        end
        if hintCells[i] then
            tint = config.hintTint
        end
        if peerCells[i] then
            tint = config.peerTint
        end
        if digit <> 0 and game.grid[i] == digit then
            tint = config.sameTint
        end
        if game.errors and game.conflicts[i] <> 0 then
            tint = config.conflictTint
        end
        if i == sel then
            tint = config.selectTint
        end
        if game.state == "won" then
            var wave = math.clamp(1 - math.abs(game.win.t * 18 - math.abs(board.rowOf[i] - board.rowOf[game.win.cell]) - math.abs(board.colOf[i] - board.colOf[game.win.cell])) / 3, 0, 1)
            if wave > 0 then
                tint = [tint[1] + (config.gold[1] - tint[1]) * wave, tint[2] + (config.gold[2] - tint[2]) * wave, tint[3] + (config.gold[3] - tint[3]) * wave, 1]
            end
        end
        fillC(tint)
        graphics.rect(x, y, c, c)
    end
    for i = 1, CELLS do
        var x, y = cellPos(i)
        var v = game.grid[i]
        if v <> 0 then
            var col = config.blue
            if game.puzzle[i] <> 0 then
                col = config.ink
            end
            if game.errors and game.conflicts[i] <> 0 then
                col = config.red
            end
            var size = c * 0.62
            if i == game.pop.cell then
                size = size * game.pop.s
            end
            drawText("{v}", x + c / 2, y + c / 2, size, "center", "center", col)
        end
    end
    graphics.fontSize(c * 0.27)
    graphics.textMode("center", "center")
    for i = 1, CELLS do
        if game.grid[i] == 0 and game.notes[i] <> 0 then
            var x, y = cellPos(i)
            for d = 1, N do
                if (game.notes[i] & (1 << d)) <> 0 then
                    var col = config.muted
                    if d == digit then
                        col = config.blue
                    end
                    graphics.stroke(col[1], col[2], col[3], col[4])
                    graphics.text("{d}", x + ((d - 1) % 3 + 0.5) * c / 3, y + ((d - 1) // 3 + 0.5) * c / 3)
                end
            end
        end
    end
    graphics.noStroke()
    for k = 0, N do
        var thick = k % BOX == 0
        var w = math.max(1, c * 0.02)
        if thick then
            w = math.max(2, c * 0.07)
            fillC(config.ink)
        else
            fillC(config.thin)
        end
        graphics.rect(L.bx + k * c - w / 2, L.by - w / 2, w, L.bs + w)
        graphics.rect(L.bx - w / 2, L.by + k * c - w / 2, L.bs + w, w)
    end
    if game.hint <> nil then
        var x, y = cellPos(game.hint.cell)
        var pulse = 0.5 + 0.5 * math.sin(elapsedTime * 6)
        graphics.noFill()
        graphics.stroke(config.amber[1], config.amber[2], config.amber[3], 0.6 + 0.4 * pulse)
        graphics.strokeSize(math.max(3, c * 0.1))
        graphics.rect(x + c * 0.06, y + c * 0.06, c * 0.88, c * 0.88, c * 0.2)
        graphics.noStroke()
    end
end

## How many of each digit are placed, so that a digit that is complete leaves the pad.
func drawPad()
    var L = game.layout
    var c = L.c
    for d = 1, N do
        var r = L.pad[d]
        var done = boardDigitCount(game.grid, d) >= N
        var fill = config.pad
        var ink = config.ink
        if done then
            fill = config.padDone
            ink = config.buttonOff
        end
        if game.input == "digit" and game.armed == d then
            fill = config.buttonOn
            ink = config.onButton
        end
        fillC(fill)
        graphics.rect(r.x, r.y, r.w, r.h, c * 0.22)
        drawText("{d}", r.x + r.w / 2, r.y + r.h / 2, math.min(r.h, c * 1.3) * 0.62, "center", "center", ink)
    end
end

func drawTools()
    var L = game.layout
    var c = L.c
    var pencilFill = config.button
    if game.pencil then
        pencilFill = config.buttonOn
    end
    var hintFill = config.button
    if game.hints <= 0 then
        hintFill = config.buttonOff
    end
    var undoFill = config.button
    if len(game.undo) == 0 then
        undoFill = config.buttonOff
    end
    drawButton(tr("pencil"), L.tools[1], pencilFill, c * 0.4)
    drawButton(tr("erase"), L.tools[2], config.button, c * 0.4)
    drawButton(tr("undo"), L.tools[3], undoFill, c * 0.4)
    drawButton("{tr("hint")} {game.hints}", L.tools[4], hintFill, c * 0.4)
end

## A text cut into the lines that fit the width at the size, breaking between words.
func wrapText(str, size, width)
    var lines = []
    var line = ""
    graphics.fontSize(size)
    for word in str.split(" ") do
        var tryLine = word
        if line <> "" then
            tryLine = line + " " + word
        end
        if graphics.textSize(tryLine) > width and line <> "" then
            lines.push(line)
            line = word
        else
            line = tryLine
        end
    end
    lines.push(line)
    return lines
end

## The line under the grid.
func drawMessage()
    var L = game.layout
    if game.message == "" then
        return
    end
    var size = L.c * 0.34
    var y = L.msg.y
    for line in wrapText(game.message, size, L.msg.w) do
        drawText(line, L.msg.x, y, size, "left", "top", config.ink)
        y += size * 1.25
    end
end

func drawWon()
    var L = game.layout
    var a = math.clamp((game.win.t - 0.4) / 0.4, 0, 1)
    if a <= 0 then
        return
    end
    var w = math.min(L.bs * 0.9, W - 2 * SIZE * config.margin)
    var h = L.c * 1.5
    var x = L.bx + L.bs / 2 - w / 2
    var y = L.by + L.bs / 2 - h / 2
    graphics.fill(1, 1, 1, a)
    graphics.rect(x, y, w, h, L.c * 0.3)
    drawText(tr("won"), x + w / 2, y + h / 2, fitSize(tr("won"), L.c * 0.8, w * 0.9), "center", "center", config.ink, a)
end

func drawPlay()
    drawHeader()
    drawBoard()
    drawMessage()
    drawPad()
    drawTools()
    drawWon()
end

## The title of a screen that replaces the game: the background is already painted.
func drawScreenTitle(title)
    drawText(title.upper(), CX, SIZE * 0.06, SIZE * 0.05, "center", "center", config.ink)
end

func drawEntries(entries)
    for i, entry in entries do
        var r = optionRect(i, len(entries))
        var fill = config.button
        if entry.primary then
            fill = config.buttonOn
        end
        drawButton(entry.label, r, fill, r.h * 0.4)
        if entry.done then
            graphics.stroke(1, 1, 1, 1)
            graphics.strokeSize(math.max(3, r.h * 0.1))
            var cx = r.x + r.w - r.h * 0.6
            var cy = r.y + r.h / 2
            graphics.line(cx - r.h * 0.18, cy, cx - r.h * 0.04, cy + r.h * 0.14)
            graphics.line(cx - r.h * 0.04, cy + r.h * 0.14, cx + r.h * 0.2, cy - r.h * 0.16)
            graphics.noStroke()
        end
    end
end

func drawGenerating()
    var dots = math.floor(elapsedTime * 3) % 4
    var text = tr("generating")
    drawText(text, CX, CY - SIZE * 0.03, fitSize(text, SIZE * 0.06, W * 0.9), "center", "center", config.ink)
    drawText(".".repeat(dots), CX, CY + SIZE * 0.05, SIZE * 0.08, "center", "center", config.muted)
    drawText(levelName(game.job.level), CX, CY + SIZE * 0.15, SIZE * 0.04, "center", "center", config.muted)
end

## ── The menus ───────────────────────────────────────────────────────────────────────────────────

func optionEntries()
    var soundKey = "menuSoundOff"
    if sounds.on then
        soundKey = "menuSoundOn"
    end
    var errorsKey = "menuErrorsOff"
    if game.errors then
        errorsKey = "menuErrorsOn"
    end
    var inputKey = "menuInputCell"
    if game.input == "digit" then
        inputKey = "menuInputDigit"
    end
    return [
        {label: tr("menuHelp"), goes: "help"},
        {label: tr("menuLanguage"), goes: "language"},
        {label: tr(soundKey), toggle: toggleSound},
        {label: tr(errorsKey), toggle: toggleErrors},
        {label: tr(inputKey), toggle: toggleInput},
        {label: tr("menuBack"), goes: "play", primary: true}
    ]
end

func languageEntries()
    var entries = []
    for code in LANGUAGES do
        entries.push({label: TEXTS[code].name, lang: code, primary: code == i18n.lang})
    end
    entries.push({label: tr("back"), goes: "options"})
    return entries
end

func newEntries()
    var entries = []
    for level = 1, 4 do
        entries.push({label: levelName(level), level: level})
    end
    entries.push({label: tr("daily"), goes: "daily", primary: true})
    entries.push({label: tr("back"), goes: "play"})
    return entries
end

func dailyEntries()
    var entries = []
    var now = today()
    for level = 1, 4 do
        entries.push({label: levelName(level), level: level, daily: now, done: game.done[dailyKey(now, level)] == true})
    end
    entries.push({label: tr("back"), goes: "new"})
    return entries
end

## A press on a menu: the entry under it, if any.
func pressEntries(entries, x, y)
    for i, entry in entries do
        if inRect(x, y, optionRect(i, len(entries))) then
            if entry.lang <> nil then
                chooseLanguage(entry.lang)
            elseif entry.toggle <> nil then
                entry.toggle()
            elseif entry.level <> nil then
                startGame(entry.level, entry.daily)
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

func helpLines(size, width)
    var lines = []
    for paragraph in tr("help")({box: BOX, size: N, hints: HINTS}) do
        for line in wrapText(paragraph, size, width) do
            lines.push(line)
        end
        lines.push("")
    end
    return lines
end

## The size and the lines of the help, wrapped again only when the area or the language changes.
func helpLayout()
    var key = "{W}x{H} {i18n.lang}"
    var cache = game.help
    if cache.key <> key then
        var width = W - 2 * SIZE * config.textMargin
        var size = SIZE * 0.04
        var lines = helpLines(size, width)
        while len(lines) * size * 1.3 > H - SIZE * 0.2 and size > 8 do
            size = size * 0.92
            lines = helpLines(size, width)
        end
        cache.key = key
        cache.size = size
        cache.lines = lines
    end
    return cache
end

func drawHelp()
    drawScreenTitle(tr("menuHelp"))
    var help = helpLayout()
    var y = SIZE * 0.12
    for line in help.lines do
        if line <> "" then
            drawText(line, SIZE * config.textMargin, y, help.size, "left", "top", config.ink)
        end
        y += help.size * 1.3
    end
    drawText(tr("tapBack"), CX, H - SIZE * 0.04, SIZE * 0.027, "center", "center", config.muted)
end

## The screens that replace the game, by name: how each is drawn and what a press on it does.
global screens = {
    options: menuScreen("options", optionEntries),
    language: menuScreen("menuLanguage", languageEntries),
    new: menuScreen("chooseLevel", newEntries),
    daily: menuScreen("daily", dailyEntries),
    help: {draw: drawHelp, press: func(x, y) showScreen("options") end},
    generating: {draw: drawGenerating, press: func(x, y) end}
}

## ── Input ───────────────────────────────────────────────────────────────────────────────────────

func pressPlay(x, y)
    var L = game.layout
    if inRect(x, y, L.gear) then
        showScreen("options")
        return
    end
    if inRect(x, y, L.newBtn) then
        showScreen("new")
        return
    end
    if game.state == "won" then
        return
    end
    for d = 1, N do
        if inRect(x, y, L.pad[d]) then
            pressDigit(d)
            return
        end
    end
    if inRect(x, y, L.tools[1]) then
        togglePencil()
    elseif inRect(x, y, L.tools[2]) then
        eraseSelected()
    elseif inRect(x, y, L.tools[3]) then
        undoMove()
    elseif inRect(x, y, L.tools[4]) then
        askHint()
    else
        var i = cellAt(x, y)
        if i <> 0 then
            pressCell(i)
        end
    end
end

## A gesture arrives twice in the same frame (touch, then the mouse the system emulates from it): the second is dropped.
func press(x, y)
    if game.tick == game.pressTick then
        return
    end
    game.pressTick = game.tick
    layoutCompute()
    if game.screen == "play" then
        pressPlay(x, y)
    else
        screens[game.screen].press(x, y)
    end
end

func touch.began(id, x, y)
    press(x, y)
end

func mouse.pressed(x, y)
    press(x, y)
end

## The keyboard, for a computer: the digits, the arrows, backspace, p for the pencil and h for a hint.
func keyboard.keypressed(key)
    if game.screen <> "play" or game.state <> "play" then
        return
    end
    var d = key.number()
    if d <> nil and d >= 1 and d <= N then
        pressDigit(d)
    elseif key == "backspace" or key == "delete" then
        eraseSelected()
    elseif key == "p" then
        togglePencil()
    elseif key == "h" then
        askHint()
    elseif key == "z" then
        undoMove()
    elseif game.selected <> 0 then
        var r = board.rowOf[game.selected]
        var c = board.colOf[game.selected]
        if key == "left" then
            c = math.max(c - 1, 1)
        elseif key == "right" then
            c = math.min(c + 1, N)
        elseif key == "up" then
            r = math.max(r - 1, 1)
        elseif key == "down" then
            r = math.min(r + 1, N)
        end
        selectCell(boardIdx(r, c))
    elseif key == "left" or key == "right" or key == "up" or key == "down" then
        selectCell(boardIdx(5, 5))
    end
end

## ── Engine entry points ─────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Sudoku")
    graphics.fitArea()
    buildSounds()
    setLanguage(data.get(config.langKey, i18n.lang))
    setSound(data.get(config.soundKey, true))
    game.errors = data.get(config.errorsKey, true) == true
    game.input = data.get(config.inputKey, "cell")
    if game.input <> "digit" then
        game.input = "cell"
    end
    loadDone()
    game.grid = boardNew()
    game.puzzle = boardNew()
    game.solution = boardNew()
    game.notes = notesNew()
    refreshConflicts()
    if not loadGame() then
        startGame(LEVEL_EASY, nil)
    end
end

func update()
    game.tick += 1
    layoutCompute()
    if game.screen == "generating" then
        updateGenerating()
    end
end

func draw()
    layoutCompute()
    graphics.clear(config.paper)
    graphics.noStroke()
    if game.screen == "play" then
        drawPlay()
    else
        screens[game.screen].draw()
    end
end
