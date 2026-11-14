## Sudoku: fill the 9x9 grid so that every row, column and 3x3 box holds the digits 1 to 9 once. The pencil notes the digits a
## cell could hold; a hint circles a cell and says how to find its digit.
##
## Two global objects hold everything: `config`, what can be tuned, and `game`, what changes as it runs. The layout follows the
## orientation of the area (graphics.fitArea) and is computed again whenever it is needed, so nothing has to be kept in step.

import "board.ol"
import "solver.ol"
import "generator.ol"
import "sounds.ol"
import "texts.ol"
import "../lib/draw.ol"
import "../lib/area.ol"
import "../lib/menu.ol"
import "layout.ol"
import "save.ol"
import "draw.ol"
import "screens.ol"


global config = {
    saveKey: "sudoku.game",
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
    done: {},                        ## the puzzles of the day solved: "20261019:2" -> true
    layout: {w: 0, h: 0, c: 0, bx: 0, by: 0, pad: [], tools: []}
}

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
    restoreLanguage()
    useMenu({ink: config.ink, muted: config.muted, button: config.button, primary: config.buttonOn, accent: config.blue, paper: config.paper,
             margin: config.margin, textMargin: config.textMargin, width: 0.8, height: 0.1, soundKey: "sudoku.sound",
             drawButton: drawButton, showScreen: showScreen})
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
