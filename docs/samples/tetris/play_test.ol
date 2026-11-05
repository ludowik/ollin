## The game of Tetris (docs/samples/tetris/play.ol), driven step by step with the input filled by hand: the clock, the
## fall, the repeat of a held direction, the turns, the soft drop, the locking, the rows that flash and fall, the score
## and the level, the pause, and the end of a game.

import "play.ol"

gameInit()
math.seed(11)

## An A game just begun at `level`: the first piece is at the top.
func begin(level)
    game.state = "level"
    game.focus = "level"
    game.type = "A"
    game.height = 0
    game.startLevel = level
    game.held = {left: false, right: false, down: false}
    game.pressed = {start: true}
    step()
    assert(game.state == "play", "a game begins on START")
end

func steps(n)
    for i = 1, n do
        step()
    end
end

## Puts the falling piece where the test wants it.
func place(kind, turn, x, y)
    game.kind = kind
    game.turn = turn
    game.x = x
    game.y = y
    game.fall = 0
    game.softFrames = 0
end

func rowsFilled(rows, except)
    for r in rows do
        for c = 0, COLS - 1 do
            if except.contains(c) then
                game.well[wellIdx(c, r)] = 0
            else
                game.well[wellIdx(c, r)] = Piece.Z
            end
        end
    end
end

func cellsFilled()
    return len(game.well.filter(func(v)
        return v <> 0
    end))
end

## ── The screens before the game ──
func press(events)
    game.pressed = events
    step()
end

game.state = "title"
press({cw: true})
press({up: true})
press({ccw: true})
assert(game.state == "title", "only START or A leaves the title, not a turn")
press({start: true})
assert(game.state == "menu" and game.focus == "type")

press({right: true})
assert(game.type == "B", "an arrow changes the type")
press({left: true})
assert(game.type == "A")
press({down: true})
assert(game.focus == "music")
var musicWas = music.on
press({right: true})
assert(music.on == not musicWas, "on the music line an arrow switches the music")
press({left: true})
assert(music.on == musicWas)
press({up: true})
assert(game.focus == "type")
press({ccw: true})
assert(game.state == "title", "B goes back")
press({confirm: true})
assert(game.state == "menu", "A leaves the title as well")
press({confirm: true})
assert(game.state == "level" and game.focus == "level")

press({left: true})
assert(game.startLevel == 0, "the level does not go below 0")
for i = 1, 12 do
    press({right: true})
end
assert(game.startLevel == config.maxStartLevel, "the level stops at {config.maxStartLevel}")
press({up: true})
assert(game.startLevel == config.maxStartLevel - 5, "up goes to the row above")
press({down: true})
assert(game.startLevel == config.maxStartLevel and game.focus == "level", "an A game has no height to choose")
press({down: true})
assert(game.focus == "level")
press({ccw: true})
assert(game.state == "menu", "B goes back to the menu")
press({confirm: true})
game.type = "B"
press({down: true})
assert(game.focus == "height", "down from the lower row of levels reaches the height of a B game")
for i = 1, 9 do
    press({right: true})
end
assert(game.height == config.maxHeight and game.startLevel == config.maxStartLevel, "the height stops at {config.maxHeight}")
press({left: true})
assert(game.height == config.maxHeight - 1)
press({up: true})
assert(game.focus == "level")
game.type = "A"

## ── A new game ──
begin(3)
assert(game.level == 3 and game.score == 0 and game.lines == 0 and cellsFilled() == 0)
assert(game.kind >= 1 and game.kind <= KINDS and game.next >= 1 and game.next <= KINDS)
assert(game.x == SPAWN_X and game.y == SPAWN_Y and game.turn == 1)
assert(data.get(config.levelKey) == 3, "the starting level is remembered")

## ── The fall: one row every fallFrames(level) frames ──
begin(0)
var y0 = game.y
steps(fallFrames(0) - 1)
assert(game.y == y0, "the piece has not moved yet")
step()
assert(game.y == y0 + 1, "one row after {fallFrames(0)} frames")
steps(fallFrames(0))
assert(game.y == y0 + 2)
begin(9)
y0 = game.y
steps(fallFrames(9))
assert(game.y == y0 + 1, "level 9 falls every {fallFrames(9)} frames")

## ── A held direction: it moves at once, repeats after the delay, then at the repeat rate ──
begin(0)
place(Piece.T, 1, 5, 4)
game.fall = -1000
game.held.left = true
step()
assert(game.x == 4, "the first move is at once")
steps(config.dasDelay - 1)
assert(game.x == 4, "then nothing during the delay")
step()
assert(game.x == 3, "the repeat starts after {config.dasDelay} frames")
steps(config.dasRepeat - 1)
assert(game.x == 3)
step()
assert(game.x == 2, "and goes on every {config.dasRepeat} frames")
game.held.left = false
steps(30)
assert(game.x == 2, "letting go stops it")
game.held.right = true
step()
assert(game.x == 3, "a new direction moves at once")
game.held.left = true
step()
assert(game.x == 3, "both held: neither moves")
game.held.left = false
game.held.right = false

## The wall stops a piece, and a filled cell does too.
place(Piece.T, 1, 0, 4)
game.held.left = true
steps(30)
assert(game.x == 0, "the left wall")
game.held.left = false
game.held.right = true
steps(5)
game.held.right = false
var xr = game.x
place(Piece.T, 1, xr, 4)
game.well[wellIdx(xr + 3, 4)] = Piece.I
game.held.right = true
steps(2)
assert(game.x == xr, "a filled cell")
game.held.right = false
game.well[wellIdx(xr + 3, 4)] = 0

## ── The turns: A clockwise, B counter-clockwise, and nothing when there is no room (no wall kick) ──
place(Piece.T, 1, 4, 6)
game.fall = -1000
game.pressed = {cw: true}
step()
assert(game.turn == 2)
game.pressed = {ccw: true}
step()
assert(game.turn == 1)
game.pressed = {ccw: true}
step()
assert(game.turn == 4, "counter-clockwise from the first position goes to the last")
place(Piece.I, 2, -2, 4)
game.fall = -1000
game.pressed = {cw: true}
step()
assert(game.turn == 2, "the bar stands against the wall: it cannot lie down there, and is not pushed away")
place(Piece.O, 1, 3, 4)
game.pressed = {cw: true}
step()
assert(game.turn == 1, "the square has one position")

## ── The soft drop: a point a row, and it has to be let go between two pieces ──
begin(0)
game.held.down = true
var yd = game.y
steps(6)
assert(game.y == yd and game.score == 0, "down held since before the piece appeared does nothing")
game.held.down = false
step()
game.held.down = true
yd = game.y
steps(config.softFrames * 3)
assert(game.y == yd + 3 and game.score == 3, "three rows of soft drop, three points")
game.held.down = false

## ── A piece comes to rest: the wait before the next one grows with the height ──
begin(0)
var nextKindWas = game.next
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
assert(game.state == "entry" and game.wait == entryDelay(ROWS - 1), "the piece rests on the floor")
assert(game.well[wellIdx(4, ROWS - 1)] == Piece.O and game.well[wellIdx(5, ROWS - 2)] == Piece.O)
steps(game.wait - 1)
assert(game.state == "entry")
step()
assert(game.state == "play" and game.kind == nextKindWas, "the piece shown as next appears")

begin(0)
rowsFilled([8], [0, 1, 2, 7, 8, 9])
place(Piece.O, 1, 3, 5)
game.fall = fallFrames(0) - 1
step()
assert(game.state == "entry" and game.wait == entryDelay(7), "a piece that rests high leaves a longer wait")
assert(game.wait > entryDelay(ROWS - 1))

## ── One row: it flashes, then goes ──
begin(0)
rowsFilled([ROWS - 1], [4, 5])
game.well[wellIdx(0, ROWS - 2)] = Piece.S
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
assert(game.state == "clearing" and game.wait == config.clearFrames)
assert(game.lines == 1 and game.score == 40, "one row at level 0 is worth 40")
assert(len(game.clearing) == 1 and game.clearing[1] == ROWS - 1)
steps(config.clearFrames - 1)
assert(game.state == "clearing", "the row is still there while it flashes")
assert(game.well[wellIdx(0, ROWS - 1)] == Piece.Z)
step()
assert(game.state == "play" and len(game.clearing) == 0)
assert(game.well[wellIdx(0, ROWS - 1)] == Piece.S, "what was above fell by one row")
assert(game.well[wellIdx(4, ROWS - 1)] == Piece.O and game.well[wellIdx(5, ROWS - 1)] == Piece.O)
assert(cellsFilled() == 3, "the row is gone: the loose cells are left")

## ── Four rows at once, with the score of the level, and a level gained ──
begin(2)
rowsFilled([ROWS - 4, ROWS - 3, ROWS - 2, ROWS - 1], [9])
place(Piece.I, 2, 7, ROWS - 4)
game.fall = fallFrames(2) - 1
step()
assert(game.lines == 4 and game.score == 1200 * 3, "four rows at level 2: 1200 times 3")
assert(game.level == 2)
steps(config.clearFrames)
assert(cellsFilled() == 0, "the four rows are gone")
begin(0)
game.lines = 8
rowsFilled([ROWS - 2, ROWS - 1], [4, 5])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
assert(game.lines == 10 and game.score == 100, "two rows are paid at the level they were made at")
assert(game.level == 1 and game.levelUp, "ten lines make level 1")
steps(config.clearFrames)
assert(game.level == 1 and not game.levelUp)
begin(5)
rowsFilled([ROWS - 1], [4, 5])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(5) - 1
step()
assert(game.lines == 1 and game.level == 5, "a game begun at level 5 stays there until ten lines are made")
begin(5)
game.lines = 9
rowsFilled([ROWS - 1], [4, 5])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(5) - 1
step()
assert(game.lines == 10 and game.level == 6, "ten lines from level 5 make level 6")

## ── A B game: the rubble, one level all along, and the goal lines that win ──
game.state = "level"
game.focus = "level"
game.type = "B"
game.startLevel = 3
game.height = 2
game.best = 0
game.held = {left: false, right: false, down: false}
press({start: true})
assert(game.state == "play" and game.level == 3 and game.lines == 0)
var rubble = cellsFilled()
assert(rubble > 0 and rubble <= 4 * (COLS - 1) and len(fullRows(game.well)) == 0, "two rows of rubble per step of height")
game.well = newWell()
game.lines = config.goalLines - 2
rowsFilled([ROWS - 1], [4, 5])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(3) - 1
step()
assert(game.lines == config.goalLines - 1 and game.level == 3 and not game.won, "a B game keeps its level")
steps(config.clearFrames)
assert(game.state == "play")
rowsFilled([ROWS - 1], [4, 5])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(3) - 1
step()
assert(game.lines == config.goalLines and game.won and game.state == "clearing")
steps(config.clearFrames)
assert(game.state == "over" and game.won, "the goal lines end the game once the rows have gone")
assert(data.get(config.bestKeyB) == game.score and game.best == game.score, "a B game keeps its own best score")
press({start: true})
assert(game.state == "over", "START waits a moment")
steps(config.wonFrames)
press({start: true})
assert(game.state == "level")
game.type = "A"
loadBest()

## ── The score has a ceiling ──
addScore(10000000)
assert(game.score == config.maxScore)

## ── The pause ──
begin(0)
var yp = game.y
game.pressed = {start: true}
step()
assert(game.state == "paused")
steps(fallFrames(0) * 2)
assert(game.y == yp and game.state == "paused", "nothing moves in a pause")
game.held.left = true
steps(10)
game.held.left = false
assert(game.y == yp)
game.pressed = {start: true}
step()
assert(game.state == "play", "START resumes")
steps(fallFrames(0))
assert(game.y == yp + 1)
game.well = newWell()
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
assert(game.state == "entry")
var waitLeft = game.wait
game.pressed = {start: true}
step()
assert(game.state == "paused")
steps(20)
game.pressed = {start: true}
step()
assert(game.state == "entry" and game.wait == waitLeft, "a pause during the wait goes back to the wait")

## ── The end of a game: the next piece has no room ──
begin(0)
rowsFilled([0], [9])
game.score = 777
game.best = 0
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
assert(game.state == "entry")
steps(game.wait)
assert(game.state == "over", "no room for the next piece")
assert(game.best == 777 and game.newBest and data.get(config.bestKey) == 777, "the best score is kept")
game.pressed = {start: true}
step()
assert(game.state == "over", "START does nothing while the curtain falls")
steps(ROWS * config.curtainFrames + 2)
assert(curtainRows() == ROWS)
press({confirm: true, cw: true})
assert(game.state == "over", "a turn pressed in the rush of the end does not leave the game over screen")
game.pressed = {start: true}
step()
assert(game.state == "level", "START after a game leaves it for the choice of a level")
begin(0)
assert(game.score == 0 and game.lines == 0 and cellsFilled() == 0 and not game.newBest, "a new game starts clean")
game.score = 100
game.well = newWell()
rowsFilled([0], [9])
place(Piece.O, 1, 3, ROWS - 3)
game.fall = fallFrames(0) - 1
step()
steps(game.wait)
assert(game.state == "over" and game.best == 777 and not game.newBest, "a lower score is not a best")

## ── The clock: 60 steps a second, a long stall catches up on a few steps only ──
begin(0)
var f0 = game.frame
game.clock = 0
advance(config.step * 3.5)
assert(game.frame == f0 + 3 and game.clock > 0.4 * config.step and game.clock < 0.6 * config.step)
advance(config.step * 0.6)
assert(game.frame == f0 + 4, "the rest of the clock is kept")
f0 = game.frame
advance(2)
assert(game.frame == f0 + config.maxSteps and game.clock == 0, "a stall is not made up for")

## The flash of the rows being cleared, and the blink of PUSH START, each on its own frames.
game.state = "clearing"
game.wait = config.clearFrames
assert(clearFlashOn() == false)
game.wait = config.clearFrames - config.clearFlash
assert(clearFlashOn() == true)
game.wait = config.clearFrames - 2 * config.clearFlash
assert(clearFlashOn() == false)
game.state = "play"
game.wait = config.clearFrames - config.clearFlash
assert(clearFlashOn() == false, "only the rows of a clearing game flash")
game.frame = 0
assert(blinkOn() == true)
game.frame = 39
assert(blinkOn() == true)
game.frame = 40
assert(blinkOn() == false)
game.frame = 60
assert(blinkOn() == true)

data.clear()
print("tetris play ok")
