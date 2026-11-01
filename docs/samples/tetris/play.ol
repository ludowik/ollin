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
    maxScore: 999999,
    maxStartLevel: 9,
    bestKey: "tetris.best",
    levelKey: "tetris.level",
    musicKey: "tetris.music"
}

## Everything that changes while the game runs.
global game = {
    state: "title",             ## title, play, clearing (full rows flash), entry (the wait before a piece), paused, over
    resume: "play",             ## where a pause returns to
    well: [],
    kind: 0,                    ## the piece falling, and its position; 0 when there is none
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
    curtain: 0,                 ## rows of the curtain that have come down, once the game is over
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
    game.curtain = 0
    game.fall = 0
    game.softFrames = 0
    game.downLock = true
    game.kind = 0
    game.next = nextKind(0)
    data.set(config.levelKey, game.startLevel)
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
    if fits(game.well, game.kind, game.turn, game.x, game.y) then
        game.state = "play"
    else
        endGame()
    end
end

func endGame()
    game.state = "over"
    game.curtain = 0
    game.wait = 0
    musicStop()
    playSound("over")
    if game.score > game.best then
        game.best = game.score
        game.newBest = game.score > 0
        data.set(config.bestKey, game.best)
    end
end

func addScore(points)
    game.score = math.min(game.score + points, config.maxScore)
end

## The piece comes to rest: it joins the well, and the full rows start to flash. The next piece waits longer when
## this one came to rest high.
func lockCurrent()
    var row = lockPiece(game.well, game.kind, game.turn, game.x, game.y)
    game.kind = 0
    game.downLock = true
    var rows = fullRows(game.well)
    if len(rows) == 0 then
        playSound("lock")
        game.state = "entry"
        game.wait = entryDelay(row)
        return
    end
    addScore(lineScore(len(rows), game.level))
    game.lines += len(rows)
    var level = levelFor(game.startLevel, game.lines)
    game.levelUp = level > game.level
    game.level = level
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
            game.fall = 0
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

func stepTitle()
    if game.pressed.left then
        game.startLevel = math.max(game.startLevel - 1, 0)
    end
    if game.pressed.right then
        game.startLevel = math.min(game.startLevel + 1, config.maxStartLevel)
    end
    if game.pressed.start then
        startGame()
    end
end

func stepOver()
    if game.curtain < ROWS then
        game.wait += 1
        if game.wait >= config.curtainFrames then
            game.wait = 0
            game.curtain += 1
        end
    elseif game.pressed.start then
        game.state = "title"
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
    game.best = data.get(config.bestKey, 0)
    game.startLevel = math.min(data.get(config.levelKey, 0), config.maxStartLevel)
    game.well = newWell()
    game.next = nextKind(0)
    buildSounds()
    music.on = data.get(config.musicKey, true)
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
    var s = game.state
    if s == "play" or s == "clearing" or s == "entry" then
        musicUpdate(dt)
    end
end
