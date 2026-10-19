## The SOLVER of Sudoku, in two forms. The SEARCH finds every solution of a grid up to a limit, so a puzzle can be
## checked for having exactly one, and fills an empty grid at random for the generator. The LOGIC solves as a person
## does, one SINGLE at a time, which grades a puzzle and tells the player what to look at.
##
## A search works on a STATE: the grid plus, for each row, column and box, the mask of the digits it holds, so that
## the digits a cell can take are one mask operation away.

const LEVEL_EASY = 1
const LEVEL_MEDIUM = 2
const LEVEL_HARD = 3
const LEVEL_EXPERT = 4
const GUESSES_HARD = 12           ## a puzzle the singles cannot solve is Hard up to this many guesses by the search, Expert past it

## The state of a grid, or nil when two of its digits clash.
func stateNew(g)
    var st = {g: [], row: [], col: [], box: [], empty: 0}
    for k = 1, N do
        st.row.push(0)
        st.col.push(0)
        st.box.push(0)
    end
    for i = 1, CELLS do
        var d = g[i]
        st.g.push(d)
        if d == 0 then
            st.empty += 1
        else
            var bit = 1 << d
            var r = board.rowOf[i]
            var c = board.colOf[i]
            var b = board.boxOf[i]
            if (st.row[r] & bit) <> 0 or (st.col[c] & bit) <> 0 or (st.box[b] & bit) <> 0 then
                return nil
            end
            st.row[r] = st.row[r] | bit
            st.col[c] = st.col[c] | bit
            st.box[b] = st.box[b] | bit
        end
    end
    return st
end

func stateCands(st, i)
    return ALL & ~(st.row[board.rowOf[i]] | st.col[board.colOf[i]] | st.box[board.boxOf[i]])
end

func statePlace(st, i, d)
    var bit = 1 << d
    st.g[i] = d
    st.row[board.rowOf[i]] = st.row[board.rowOf[i]] | bit
    st.col[board.colOf[i]] = st.col[board.colOf[i]] | bit
    st.box[board.boxOf[i]] = st.box[board.boxOf[i]] | bit
    st.empty -= 1
end

func stateRemove(st, i, d)
    var bit = ~(1 << d)
    st.g[i] = 0
    st.row[board.rowOf[i]] = st.row[board.rowOf[i]] & bit
    st.col[board.colOf[i]] = st.col[board.colOf[i]] & bit
    st.box[board.boxOf[i]] = st.box[board.boxOf[i]] & bit
    st.empty += 1
end

## ── The random numbers: a small generator of our own, so that a seed gives the same sequence on every platform ──

func rngNew(seed)
    var s = seed & 0xFFFFFFFF
    if s == 0 then
        s = 2463534242
    end
    var rng = {s: s}
    for k = 1, 8 do
        rngNext(rng)
    end
    return rng
end

## xorshift32: 32 bits kept by hand, the integers being 64 bits wide.
func rngNext(rng)
    var x = rng.s
    x = x ~ ((x << 13) & 0xFFFFFFFF)
    x = x ~ (x >> 17)
    x = x ~ ((x << 5) & 0xFFFFFFFF)
    rng.s = x
    return x
end

## An integer from 1 to n.
func rngInt(rng, n)
    return rngNext(rng) % n + 1
end

func shuffled(list, rng)
    var out = []
    for v in list do
        out.push(v)
    end
    for i = len(out), 2, -1 do
        var j = rngInt(rng, i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

## ── The search ──────────────────────────────────────────────────────────────────────────────────

## Looks for the solutions of the state, on the cell with the fewest candidates, until `limit` are found. With an
## rng the digits are tried in a random order. `found` gets the count, the first solution, and how many cells were
## guessed on (a cell with more than one candidate).
func solverSearch(st, limit, found, rng)
    if st.empty == 0 then
        found.count += 1
        if found.solution == nil then
            found.solution = boardCopy(st.g)
        end
        return
    end
    var best = 0
    var bestMask = 0
    var bestN = N + 1
    for i = 1, CELLS do
        if st.g[i] == 0 then
            var m = stateCands(st, i)
            var n = maskCount(m)
            if n < bestN then
                best = i
                bestMask = m
                bestN = n
                if n <= 1 then
                    break
                end
            end
        end
    end
    if bestN == 0 then
        return
    end
    if bestN > 1 then
        found.guesses += 1
    end
    var digits = maskDigits(bestMask)
    if rng <> nil then
        digits = shuffled(digits, rng)
    end
    for d in digits do
        statePlace(st, best, d)
        solverSearch(st, limit, found, rng)
        stateRemove(st, best, d)
        if found.count >= limit then
            return
        end
    end
end

## {count, solution, guesses} for a grid, stopping at `limit` solutions. A grid whose digits clash has none.
func solverCount(g, limit, rng)
    var found = {count: 0, solution: nil, guesses: 0}
    var st = stateNew(g)
    if st <> nil then
        solverSearch(st, limit, found, rng)
    end
    return found
end

## A complete grid, drawn at random.
func solverFill(rng)
    return solverCount(boardNew(), 1, rng).solution
end

## ── The logic ───────────────────────────────────────────────────────────────────────────────────

## Which unit unit number u (1 to 27) is: "row", "column" or "box", and its number among those.
func unitInfo(u)
    if u <= N then
        return "row", u
    elseif u <= 2 * N then
        return "column", u - N
    end
    return "box", u - 2 * N
end

## The next SINGLE of a state, or nil: a cell that can take one digit only ("naked"), or, when `hidden`, a digit that
## fits one cell only of a row, a column or a box ("hidden"). A naked single wins over a hidden one.
func nextSingle(st, hidden)
    for i = 1, CELLS do
        if st.g[i] == 0 then
            var m = stateCands(st, i)
            if maskCount(m) == 1 then
                return {cell: i, digit: maskLow(m), kind: "naked"}
            end
        end
    end
    if not hidden then
        return nil
    end
    for u, unit in board.units do
        var cells = []
        var masks = []
        var have = 0
        for i in unit do
            if st.g[i] == 0 then
                cells.push(i)
                masks.push(stateCands(st, i))
            else
                have = have | (1 << st.g[i])
            end
        end
        for d = 1, N do
            var bit = 1 << d
            if (have & bit) == 0 then
                var where = 0
                var n = 0
                for k, i in cells do
                    if (masks[k] & bit) <> 0 then
                        n += 1
                        where = i
                    end
                end
                if n == 1 then
                    return {cell: where, digit: d, kind: "hidden", unit: u}
                end
            end
        end
    end
    return nil
end

## Solves a grid with singles alone: {solved, steps}.
func logicSolve(g, hidden)
    var st = stateNew(g)
    if st == nil then
        return {solved: false, steps: 0}
    end
    var steps = 0
    while true do
        var move = nextSingle(st, hidden)
        if move == nil then
            break
        end
        statePlace(st, move.cell, move.digit)
        steps += 1
    end
    return {solved: st.empty == 0, steps: steps}
end

## How hard a puzzle is: Easy when the naked singles solve it, Medium when the hidden ones are needed too, and
## otherwise Hard or Expert by how many cells the search has to guess on. {level, guesses}.
func puzzleGrade(g)
    if logicSolve(g, false).solved then
        return {level: LEVEL_EASY, guesses: 0}
    end
    if logicSolve(g, true).solved then
        return {level: LEVEL_MEDIUM, guesses: 0}
    end
    var guesses = solverCount(g, 1, nil).guesses
    if guesses <= GUESSES_HARD then
        return {level: LEVEL_HARD, guesses: guesses}
    end
    return {level: LEVEL_EXPERT, guesses: guesses}
end

## What to tell the player who asks for a hint on grid g, whose solution is known: a digit that is wrong comes first,
## then the next single, and when there is none the cell with the fewest candidates, given plainly.
## {kind: "mistake" | "naked" | "hidden" | "plain", cell, digit, unit}
func hintFor(g, solution)
    for i = 1, CELLS do
        if g[i] <> 0 and g[i] <> solution[i] then
            return {kind: "mistake", cell: i, digit: solution[i]}
        end
    end
    var st = stateNew(g)
    var move = nextSingle(st, true)
    if move <> nil then
        return move
    end
    var best = 0
    var bestN = N + 1
    for i = 1, CELLS do
        if g[i] == 0 then
            var n = maskCount(stateCands(st, i))
            if n < bestN then
                best = i
                bestN = n
            end
        end
    end
    return {kind: "plain", cell: best, digit: solution[best]}
end
