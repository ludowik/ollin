## The GAME of Tetris, with no input device and no drawing: its state, the clock of 60 steps a second, and what
## each state does in a step — a piece falling, the waits, the rows that flash, the curtain of a lost game, the pause.
## The input arrives as `game.held` (a direction or down, held) and `game.pressed` (a turn, START, an arrow, pressed
## since the last step), which tetris.ol fills from the keyboard and the pads and play_test.ol fills by hand.
##
## rules.ol holds the rules, sounds.ol the sound. The two objects below hold everything: `config`, what can be
## tuned, and `game`, what changes as it runs.

import "rules.ol"
import "sounds.ol"

## What can be tuned: the clock, the waits and the keys of the saved data.
global config = {
    step: 1 / 60,               ## seconds of one step of the game
    maxSteps: 5,                ## steps one frame may catch up on after a stall
    dasDelay: 16,               ## frames a direction is held before it repeats
    dasRepeat: 6,               ## frames between two moves once it repeats
    softFrames: 2,              ## frames between two rows of a soft drop
    clearFrames: 20,            ## frames the full rows flash
    clearFlash: 4,              ## frames of one flash
    curtainFrames: 2,           ## frames between two rows of the curtain that ends a game
    wonFrames: 60,              ## frames before START is heard once a B game is won
    goalLines: 25,              ## the lines that win a B game
    maxScore: 999999,
    maxStartLevel: 9,
    maxHeight: 5,
    bestKey: "tetris.best",     ## the best score of an A game; the one of a B game is kept apart
    bestKeyB: "tetris.bestB",
    typeKey: "tetris.type",
    levelKey: "tetris.level",
    heightKey: "tetris.height",
    musicKey: "tetris.music"
}

## Everything that changes while the game runs.
global game = {
    state: "title",             ## title, menu (type and music), level (level and height), play, clearing (full rows
                                ## flash), entry (the wait before a piece), paused, over
    focus: "type",              ## what the arrows move on the menu (type, music) and level (level, height) screens
    type: "A",                  ## A climbs level by level; B stays at one level and ends at the goal lines
    height: 0,                  ## the rubble a B game starts with
    won: false,                 ## the B game was won
    resume: "play",             ## where a pause returns to
    well: [],
    kind: 0,                    ## the piece falling, and its position, while the state is play
    turn: 1,
    x: 0,
    y: 0,
    next: 1,
    score: 0,
    lines: 0,
    level: 0,
    startLevel: 0,
    best: 0,
    newBest: false,
    fall: 0,                    ## frames since the piece last dropped
    softFrames: 0,              ## frames since the last row of a soft drop
    downLock: false,            ## down must be let go before it drops the next piece
    dasDir: 0,
    dasFrames: 0,
    wait: 0,                    ## frames left of a clearing or of the wait before a piece
    clearing: [],               ## the rows that flash
    levelUp: false,             ## the lines in flight raised the level
    frame: 0,                   ## steps since the program began, which blinks the texts
    clock: 0,                   ## seconds not yet spent in steps
    held: {left: false, right: false, down: false},
    pressed: {}                 ## what was pressed since the last step: cw, ccw, start, left, right
}

## ── Starting, spawning, locking ────────────────────────────────────────────────────────────────────

func startGame()
    game.well = newWell()
    game.score = 0
    game.lines = 0
    game.level = game.startLevel
    game.newBest = false
    game.levelUp = false
    game.won = false
    if game.type == "B" then
        addGarbage(game.well, game.height)
    end
    game.next = nextKind(0)
    data.set(config.typeKey, game.type)
    data.set(config.levelKey, game.startLevel)
    data.set(config.heightKey, game.height)
    playSound("start")
    musicRestart()
    spawnPiece()
end

## The next piece appears at the top; when it has no room the game is over.
func spawnPiece()
    game.kind = game.next
    game.next = nextKind(game.kind)
    game.turn = 1
    game.x = SPAWN_X
    game.y = SPAWN_Y
    game.fall = 0
    game.softFrames = 0
    game.downLock = true
    if fits(game.well, game.kind, game.turn, game.x, game.y) then
        game.state = "play"
    else
        endGame()
    end
end

func bestKey()
    return game.type == "A" and config.bestKey or config.bestKeyB
end

func loadBest()
    game.best = data.get(bestKey(), 0)
end

func endGame()
    game.state = "over"
    game.wait = 0
    musicStop()
    playSound(game.won and "level" or "over")
    if game.score > game.best then
        game.best = game.score
        game.newBest = game.score > 0
        data.set(bestKey(), game.best)
    end
end

## The lines the panel shows: those made in an A game, those still to make in a B game.
func linesShown()
    if game.type == "A" then
        return game.lines
    end
    return math.max(config.goalLines - game.lines, 0)
end

func addScore(points)
    game.score = math.min(game.score + points, config.maxScore)
end

## The piece comes to rest: it joins the well, and the full rows start to flash. The next piece waits longer when
## this one came to rest high.
func lockCurrent()
    var row = lockPiece(game.well, game.kind, game.turn, game.x, game.y)
    var rows = fullRows(game.well)
    if len(rows) == 0 then
        playSound("lock")
        game.state = "entry"
        game.wait = entryDelay(row)
        return
    end
    addScore(lineScore(len(rows), game.level))
    game.lines += len(rows)
    var level = levelFor(game.startLevel, game.lines, game.type)
    game.levelUp = level > game.level
    game.level = level
    game.won = game.type == "B" and game.lines >= config.goalLines
    game.clearing = rows
    game.state = "clearing"
    game.wait = config.clearFrames
    if len(rows) >= 4 then
        playSound("tetris")
    else
        playSound("lines")
    end
end

## ── The steps ──────────────────────────────────────────────────────────────────────────────────────

func tryMove(dx)
    if fits(game.well, game.kind, game.turn, game.x + dx, game.y) then
        game.x += dx
        playSound("move")
    end
end

func tryTurn(dir)
    var t = turnedBy(game.kind, game.turn, dir)
    if fits(game.well, game.kind, t, game.x, game.y) then
        game.turn = t
        playSound("turn")
    end
end

## One row down, or the end of the fall. A soft drop pays a point a row.
func dropOne(soft)
    if fits(game.well, game.kind, game.turn, game.x, game.y + 1) then
        game.y += 1
        game.fall = 0
        if soft then
            addScore(1)
        end
    else
        lockCurrent()
    end
end

func stepPlay()
    var held = game.held
    var dir = 0
    if held.left and not held.right then
        dir = -1
    elseif held.right and not held.left then
        dir = 1
    end
    if dir == 0 then
        game.dasDir = 0
        game.dasFrames = 0
    elseif dir <> game.dasDir then
        game.dasDir = dir
        game.dasFrames = 0
        tryMove(dir)
    else
        game.dasFrames += 1
        if game.dasFrames >= config.dasDelay then
            tryMove(dir)
            game.dasFrames = config.dasDelay - config.dasRepeat
        end
    end
    if game.pressed.cw then
        tryTurn(1)
    end
    if game.pressed.ccw then
        tryTurn(-1)
    end
    if not held.down then
        game.downLock = false
    end
    if held.down and not game.downLock then
        game.softFrames += 1
        if game.softFrames >= config.softFrames then
            game.softFrames = 0
            dropOne(true)
        end
    else
        game.softFrames = 0
        game.fall += 1
        if game.fall >= fallFrames(game.level) then
            dropOne(false)
        end
    end
end

func stepClearing()
    game.wait -= 1
    if game.wait > 0 then
        return
    end
    collapse(game.well, game.clearing)
    game.clearing = []
    if game.won then
        endGame()
        return
    end
    if game.levelUp then
        game.levelUp = false
        playSound("level")
    end
    spawnPiece()
end

func stepEntry()
    game.wait -= 1
    if game.wait <= 0 then
        spawnPiece()
    end
end

## What the keys that confirm and go back do on the screens before the game.
func confirmed()
    return game.pressed.start or game.pressed.confirm
end

func stepTitle()
    if confirmed() then
        game.state = "menu"
        game.focus = "type"
    end
end

func stepMenu()
    var p = game.pressed
    if p.up or p.down then
        game.focus = game.focus == "type" and "music" or "type"
    end
    if p.left or p.right then
        if game.focus == "type" then
            game.type = game.type == "A" and "B" or "A"
            loadBest()
        else
            setMusic(not music.on)
        end
    end
    if confirmed() then
        game.state = "level"
        game.focus = "level"
    elseif p.ccw then
        game.state = "title"
    end
end

func stepLevel()
    var p = game.pressed
    var d = (p.right and 1 or 0) - (p.left and 1 or 0)
    if d <> 0 then
        if game.focus == "level" then
            game.startLevel = math.clamp(game.startLevel + d, 0, config.maxStartLevel)
        else
            game.height = math.clamp(game.height + d, 0, config.maxHeight)
        end
    end
    if p.up then
        if game.focus == "height" then
            game.focus = "level"
        elseif game.startLevel >= 5 then
            game.startLevel -= 5
        end
    end
    if p.down and game.focus == "level" then
        if game.startLevel < 5 then
            game.startLevel += 5
        elseif game.type == "B" then
            game.focus = "height"
        end
    end
    if confirmed() then
        startGame()
    elseif p.ccw then
        game.state = "menu"
        game.focus = "type"
    end
end

## The frames the end of a game lasts before START is heard: the curtain falling, or the wait of a won game.
func overFrames()
    return game.won and config.wonFrames or ROWS * config.curtainFrames
end

func overDone()
    return game.wait >= overFrames()
end

## The rows of the curtain that have come down on a lost game.
func curtainRows()
    return math.min(game.wait // config.curtainFrames, ROWS)
end

func stepOver()
    if not overDone() then
        game.wait += 1
    elseif game.pressed.start then
        game.state = "level"
        game.focus = "level"
    end
end

func pauseGame()
    game.resume = game.state
    game.state = "paused"
    musicStop()
end

func step()
    game.frame += 1
    var state = game.state
    if state == "title" then
        stepTitle()
    elseif state == "menu" then
        stepMenu()
    elseif state == "level" then
        stepLevel()
    elseif state == "over" then
        stepOver()
    elseif game.pressed.start then
        if state == "paused" then
            game.state = game.resume
        else
            pauseGame()
        end
    elseif state == "play" then
        stepPlay()
    elseif state == "clearing" then
        stepClearing()
    elseif state == "entry" then
        stepEntry()
    end
    game.pressed = {}
end

## Switches the music, and remembers the choice.
func setMusic(on)
    music.on = on
    data.set(config.musicKey, on)
    if not on then
        musicStop()
    end
end

## Begins the program: the saved best score, level and music, the sounds, an empty well.
func gameInit()
    game.type = data.get(config.typeKey, "A") == "B" and "B" or "A"
    loadBest()
    game.startLevel = math.clamp(data.get(config.levelKey, 0), 0, config.maxStartLevel)
    game.height = math.clamp(data.get(config.heightKey, 0), 0, config.maxHeight)
    buildSounds()
    music.on = data.get(config.musicKey, true)
end

## A game is on: a piece falls or the game waits between two of them.
func running()
    var s = game.state
    return s == "play" or s == "clearing" or s == "entry"
end

## Spends dt seconds in steps of the game, and plays the music while a game is on.
func advance(dt)
    game.clock += dt
    var steps = 0
    while game.clock >= config.step and steps < config.maxSteps do
        step()
        game.clock -= config.step
        steps += 1
    end
    if steps == config.maxSteps then
        game.clock = 0
    end
    if running() then
        musicUpdate(dt)
    end
end
