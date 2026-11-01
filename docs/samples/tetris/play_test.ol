## The game of Tetris (docs/samples/tetris/play.ol), driven step by step with the input filled by hand: the clock, the
## fall, the repeat of a held direction, the turns, the soft drop, the locking, the rows that flash and fall, the score
## and the level, the pause, and the end of a game.

import "play.ol"

gameInit()
math.seed(11)

## A game just begun at `level`: the first piece is at the top.
func begin(level)
    game.state = "title"
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

## ── The title screen ──
game.pressed = {left: true}
step()
assert(game.startLevel == 0, "the level does not go below 0")
for i = 1, 12 do
    game.pressed = {right: true}
    step()
end
assert(game.startLevel == config.maxStartLevel, "the level stops at {config.maxStartLevel}")
game.pressed = {left: true}
step()
assert(game.startLevel == config.maxStartLevel - 1)
assert(game.state == "title")
game.pressed = {cw: true}
step()
game.pressed = {ccw: true}
step()
assert(game.state == "title", "only START starts a game, not a turn (the arrows may be tried on the title screen)")

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
assert(game.lines == 1 and game.level == 5, "a game begun at level 5 stays there until level 6 is earned")

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
game.pressed = {start: true}
step()
assert(game.state == "title")
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

data.clear()
print("tetris play ok")
