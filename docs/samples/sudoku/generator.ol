## The GENERATOR of Sudoku: a complete grid drawn at random, then cells taken out one by one as long as the grid
## keeps ONE solution, down to the number of clues the level asks for. The puzzle is then graded by the logic
## (solver.ol); one that is not of the level wanted is thrown away and another is drawn, a few times over, and the
## nearest one is kept when none was right.
##
## A puzzle only depends on its seed: the random numbers are our own (rngNew), so the same seed gives the same puzzle
## on every platform, which is what the puzzle of the day relies on. It is made by a JOB that advances a little at a
## time, so that a screen can keep drawing while a hard puzzle is being cut; the steps change nothing in the result.

## The clues a puzzle of each level is cut down to, as a range the draw picks in: the easy levels stop early, the
## hard ones are taken as far as the uniqueness allows.
const CLUES = [[36, 40], [30, 34], [22, 28], [17, 24]]
const ATTEMPTS = 8

## Starts a puzzle of the level (1 to 4) for a seed.
func generatorNew(seed, level)
    var job = {rng: rngNew(seed), level: level, attempt: 0, best: nil, result: nil, solution: nil, g: nil, order: nil, pos: 0, clues: 0, target: 0}
    generatorAttempt(job)
    return job
end

## Begins an attempt: a complete grid, the order the cells will be tried in, and the clues to stop at.
func generatorAttempt(job)
    var rng = job.rng
    var range = CLUES[job.level]
    var cells = []
    for i = 1, CELLS do
        cells.push(i)
    end
    job.attempt += 1
    job.solution = solverFill(rng)
    job.g = boardCopy(job.solution)
    job.target = range[1] + rngInt(rng, range[2] - range[1] + 1) - 1
    job.order = shuffled(cells, rng)
    job.pos = 0
    job.clues = CELLS
end

## Grades the finished attempt, and keeps it when it is of the level wanted or nearer to it than the best so far.
func generatorFinish(job)
    var grade = puzzleGrade(job.g)
    var found = {puzzle: job.g, solution: job.solution, level: grade.level, guesses: grade.guesses, clues: job.clues}
    if grade.level == job.level or job.attempt >= ATTEMPTS then
        if grade.level <> job.level and job.best <> nil and math.abs(job.best.level - job.level) < math.abs(grade.level - job.level) then
            found = job.best
        end
        job.result = found
        return
    end
    if job.best == nil or math.abs(grade.level - job.level) < math.abs(job.best.level - job.level) then
        job.best = found
    end
    generatorAttempt(job)
end

## Works for about `seconds` of processor time; true once the puzzle is made (job.result).
func generatorStep(job, seconds)
    var t0 = cpuTime()
    while job.result == nil do
        if job.pos >= CELLS or job.clues <= job.target then
            generatorFinish(job)
        else
            job.pos += 1
            var i = job.order[job.pos]
            var d = job.g[i]
            job.g[i] = 0
            if solverCount(job.g, 2, nil).count == 1 then
                job.clues -= 1
            else
                job.g[i] = d
            end
        end
        if cpuTime() - t0 >= seconds then
            break
        end
    end
    return job.result <> nil
end

## {puzzle, solution, level, guesses, clues} for a seed and a level, all at once.
func generatePuzzle(seed, level)
    var job = generatorNew(seed, level)
    while not generatorStep(job, 1000) do
    end
    return job.result
end

## A calendar day as one number: 20261019.
func dayNumber(year, month, day)
    return year * 10000 + month * 100 + day
end

## The seed of the puzzle of a day and a level: the date in the local calendar, each level its own.
func dailySeed(year, month, day, level)
    return dayNumber(year, month, day) * 8 + level
end
