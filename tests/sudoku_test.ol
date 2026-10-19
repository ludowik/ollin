## The Sudoku sample (docs/samples/sudoku): the rules, the solver, the generator and the hints, with no drawing.

import "../docs/samples/sudoku/board.ol"
import "../docs/samples/sudoku/solver.ol"
import "../docs/samples/sudoku/generator.ol"

func parse(text)
    return boardDecode(text.replace(".", "0"))
end

const EASY = "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
const EASY_SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
## Arto Inkala's puzzle, known as one of the hardest: the singles do not solve it.
const INKALA = "8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4.."

## ── The tables and the rules ────────────────────────────────────────────────────────────────────
assert(len(board.units) == 27 and len(board.peers) == CELLS, "27 units, a list of peers per cell")
for unit in board.units do
    assert(len(unit) == 9, "a unit holds nine cells")
end
for list in board.peers do
    assert(len(list) == 20, "a cell has twenty peers")
end
assert(boardIdx(1, 1) == 1 and boardIdx(9, 9) == 81 and board.boxOf[boardIdx(5, 5)] == 5 and board.boxOf[boardIdx(4, 7)] == 6)
assert(maskCount(ALL) == 9 and maskCount(0) == 0 and maskLow(0b101000) == 3 and maskDigits(0b101000).join() == "35")

var g = parse(EASY)
assert(boardFilled(g) == 30 and not boardHasConflict(g) and not boardComplete(g))
assert(maskDigits(boardCandidates(g, boardIdx(1, 3))).join() == "124", "the candidates of a cell: {maskDigits(boardCandidates(g, boardIdx(1, 3))).join()}")
var clash = boardCopy(g)
clash[boardIdx(1, 3)] = 5
var marks = boardConflicts(clash)
assert(marks[boardIdx(1, 3)] == 1 and marks[boardIdx(1, 1)] == 1 and marks[boardIdx(9, 9)] == 0, "a digit repeated in a row is marked, with its twin")
assert(boardHasConflict(clash))
assert(boardComplete(parse(EASY_SOLUTION)), "the known solution is complete")
assert(boardDigitCount(parse(EASY_SOLUTION), 5) == 9)

## Notes: a mask per cell, toggled, and cleaned from the peers of a digit placed.
var notes = notesNew()
notesToggle(notes, 1, 4)
notesToggle(notes, 2, 4)
notesToggle(notes, 2, 7)
assert(notes[1] == 1 << 4 and maskDigits(notes[2]).join() == "47")
notesToggle(notes, 1, 4)
assert(notes[1] == 0, "a second toggle takes the note away")
notesClean(notes, 1, 4)
assert(notes[2] == 1 << 7, "the digit placed leaves the notes of its peers (cell 2 shares a row with cell 1)")

## The saved text: 81 digits, and nothing else is accepted.
assert(boardEncode(g) == EASY.replace(".", "0"))
assert(boardDecode(boardEncode(g)).join() == g.join(), "encode then decode gives the grid back")
assert(boardDecode("123") == nil and boardDecode(g.join() + "0") == nil and boardDecode(nil) == nil and boardDecode(5) == nil)
assert(boardDecode("x" + EASY.replace(".", "0").substr(2, 80)) == nil, "a character that is not a digit is refused")

## The saved game: a text that gives everything back, and refuses what is not one.
var puzzleText = EASY.replace(".", "0")
var played = boardDecode(puzzleText)
played[3] = 4
var savedNotes = notesNew()
savedNotes[4] = 0b1010
var text = gameEncode(boardDecode(puzzleText), played, savedNotes, 2, 3, {year: 2026, month: 10, day: 19})
var back = gameDecode(text, 3, 4)
assert(back <> nil and back.puzzle.join() == puzzleText and back.grid.join() == played.join() and back.notes[4] == 0b1010 and back.notes[5] == 0, "a saved game reads back")
assert(back.hints == 2 and back.level == 3 and back.daily.year == 2026 and back.daily.month == 10 and back.daily.day == 19)
var plain = gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 0, 1, nil), 3, 4)
assert(plain <> nil and plain.daily == nil and plain.hints == 0 and plain.level == 1, "a game of no day")
assert(gameDecode(nil, 3, 4) == nil and gameDecode("", 3, 4) == nil and gameDecode("a|b|c", 3, 4) == nil)
assert(gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 4, 3, nil), 3, 4) == nil, "more hints than the game gives")
assert(gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 2, 5, nil), 3, 4) == nil and gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 2, 0, nil), 3, 4) == nil, "a level out of range")
var forged = boardCopy(played)
forged[1] = 9
assert(gameDecode(gameEncode(boardDecode(puzzleText), forged, savedNotes, 2, 3, nil), 3, 4) == nil, "a grid that lost a clue")
var badNotes = notesNew()
badNotes[2] = 1024
assert(gameDecode(gameEncode(boardDecode(puzzleText), played, badNotes, 2, 3, nil), 3, 4) == nil, "a note outside the digits")
assert(gameDecode(text.replace("2026,10,19", "2026,10"), 3, 4) == nil and gameDecode(text.replace("2026,10,19", "a,b,c"), 3, 4) == nil, "a day that is not one")
assert(gameDecode(text + "|x", 3, 4) == nil, "a text with a part too many")
assert(gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 1.5, 3, nil), 3, 4) == nil and gameDecode(gameEncode(boardDecode(puzzleText), played, savedNotes, 2, 2.5, nil), 3, 4) == nil, "a hint count or a level that is not whole")
assert(gameDecode(text.replace("2026,10,19", "2026,10,1.5"), 3, 4) == nil, "a day that is not whole")
var halfNotes = boardCopy(savedNotes)
halfNotes[3] = 1.5
assert(gameDecode(gameEncode(boardDecode(puzzleText), played, halfNotes, 2, 3, nil), 3, 4) == nil, "a note that is not whole")

## ── The solver ──────────────────────────────────────────────────────────────────────────────────
var found = solverCount(g, 2, nil)
assert(found.count == 1 and found.solution.join() == EASY_SOLUTION, "the easy puzzle has one solution")
assert(solverCount(boardNew(), 2, nil).count == 2, "an empty grid has many solutions; the count stops at the limit")
assert(solverCount(clash, 2, nil).count == 0, "a grid whose digits clash has none")
var dead = boardNew()
for c = 1, 8 do
    dead[boardIdx(1, c)] = c
end
dead[boardIdx(2, 9)] = 9
dead[boardIdx(3, 9)] = 9
assert(solverCount(dead, 2, nil).count == 0, "two 9 in a column: no solution")
var loose = boardCopy(g)
var removed = 0
for i = 1, CELLS do
    if loose[i] <> 0 and solverCount(loose, 2, nil).count == 1 then
        loose[i] = 0
        removed += 1
    end
end
assert(solverCount(loose, 2, nil).count == 2, "taking every clue out that can go leaves a puzzle with several solutions")

## The random numbers: a seed gives the same sequence, and the numbers stay in range.
var r1 = rngNew(42)
var r2 = rngNew(42)
var r3 = rngNew(43)
var same = true
var differs = false
for k = 1, 20 do
    var a = rngNext(r1)
    same = same and a == rngNext(r2)
    differs = differs or a <> rngNext(r3)
end
assert(same and differs, "the same seed gives the same numbers, another seed other ones")
var seen = {}
for k = 1, 400 do
    var v = rngInt(r1, 9)
    assert(v >= 1 and v <= 9, "rngInt out of range: {v}")
    seen[v] = true
end
assert(len(seen) == 9, "all nine values come up")
assert(shuffled([1, 2, 3, 4, 5], rngNew(1)).sort(func(a, b) return a < b end).join() == "12345", "a shuffle keeps the elements")
for seed in [1, 2, 3] do
    var full = solverFill(rngNew(seed))
    assert(boardComplete(full), "seed {seed}: the filled grid is a valid solution")
end
assert(solverFill(rngNew(7)).join() == solverFill(rngNew(7)).join() and solverFill(rngNew(7)).join() <> solverFill(rngNew(8)).join())

## ── The logic and the grade ─────────────────────────────────────────────────────────────────────
assert(logicSolve(g, false), "the naked singles solve the easy puzzle")
assert(puzzleGrade(g).level == LEVEL_EASY)
var inkala = parse(INKALA)
assert(solverCount(inkala, 2, nil).count == 1, "Inkala's puzzle has one solution")
assert(not logicSolve(inkala, true), "the singles do not solve it")
assert(puzzleGrade(inkala).level >= LEVEL_HARD, "and it is Hard or Expert")

## ── The hints ───────────────────────────────────────────────────────────────────────────────────
var solution = parse(EASY_SOLUTION)
var hint = hintFor(g, solution)
assert(hint.kind == "naked" or hint.kind == "hidden", "the first hint is a single: {hint.kind}")
assert(hint.digit == solution[hint.cell] and g[hint.cell] == 0)
var wrong = boardCopy(g)
wrong[boardIdx(1, 3)] = 1
var mistake = hintFor(wrong, solution)
assert(mistake.kind == "mistake" and mistake.cell == boardIdx(1, 3) and mistake.digit == solution[boardIdx(1, 3)], "a wrong digit comes first")

## Following the hints from a puzzle always leads to its solution, and what a hint says is true.
for level = 1, 3 do
    var p = generatePuzzle(500 + level, level)
    var play = boardCopy(p.puzzle)
    var guard = 0
    while boardFilled(play) < CELLS do
        var h = hintFor(play, p.solution)
        assert(h.kind <> "mistake" and h.digit == p.solution[h.cell] and play[h.cell] == 0, "level {level}: a hint is right")
        if h.kind == "naked" then
            assert(boardCandidates(play, h.cell) == 1 << h.digit, "a naked single: the cell takes that digit only")
        elseif h.kind == "hidden" then
            var kind, n = unitInfo(h.unit)
            var fits = 0
            for i in board.units[h.unit] do
                if play[i] == 0 and (boardCandidates(play, i) & (1 << h.digit)) <> 0 then
                    fits += 1
                end
            end
            assert(fits == 1 and kind <> "" and n >= 1 and n <= 9, "a hidden single: the digit fits one cell of the {kind} {n}")
        end
        play[h.cell] = h.digit
        guard += 1
        assert(guard <= CELLS, "the hints must end")
    end
    assert(boardComplete(play) and play.join() == p.solution.join(), "level {level}: the hints lead to the solution")
end

## ── The generator ───────────────────────────────────────────────────────────────────────────────
for level = 1, 4 do
    for seed in [11, 12, 13] do
        var p = generatePuzzle(seed * 10 + level, level)
        assert(boardFilled(p.puzzle) == p.clues and p.clues <= CELLS)
        var count = solverCount(p.puzzle, 2, nil)
        assert(count.count == 1 and count.solution.join() == p.solution.join(), "level {level} seed {seed}: one solution, the one kept")
        for i = 1, CELLS do
            assert(p.puzzle[i] == 0 or p.puzzle[i] == p.solution[i], "a clue is a digit of the solution")
        end
        assert(math.abs(p.level - level) <= 1, "level {level} seed {seed}: graded {p.level}")
        if level <= 2 then
            assert(p.level == level and p.clues >= CLUES[level][1] and p.clues <= CLUES[level][2], "level {level} seed {seed}: graded {p.level} with {p.clues} clues")
        end
        assert(p.guesses >= 0)
    end
end
var twice = generatePuzzle(777, 2)
assert(twice.puzzle.join() == generatePuzzle(777, 2).puzzle.join(), "the same seed gives the same puzzle")
assert(twice.puzzle.join() <> generatePuzzle(778, 2).puzzle.join(), "another seed gives another")

## A job advanced in small steps ends on the same puzzle as the one made at once.
var job = generatorNew(777, 2)
var steps = 0
while not generatorStep(job, 0) do
    steps += 1
end
assert(steps > 5 and job.result.puzzle.join() == twice.puzzle.join(), "steps change nothing to the result: {steps} steps")

## The puzzle of the day: a date and a level give one seed; the days and the levels differ.
assert(dailySeed(2026, 10, 19, 1) == dailySeed(2026, 10, 19, 1))
assert(dailySeed(2026, 10, 19, 1) <> dailySeed(2026, 10, 19, 2) and dailySeed(2026, 10, 19, 1) <> dailySeed(2026, 10, 20, 1))
assert(generatePuzzle(dailySeed(2026, 10, 19, 2), 2).puzzle.join() == generatePuzzle(dailySeed(2026, 10, 19, 2), 2).puzzle.join())
print("sudoku ok")
