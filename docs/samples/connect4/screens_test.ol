## What touches, clicks and keys do on Connect Four's screens (docs/samples/connect4/screens.ol): the title's choices, aiming a disc and
## dropping it where the finger lifts, the buttons of a game and of its end, and the keys. The rectangles are the drawing's own.

import "screens.ol"
import "connect4_testlib.ol"

func centre(r)
    return r.x + r.w / 2, r.y + r.h / 2
end

func tapRect(r)
    var x, y = centre(r)
    pointerDown("mouse", x, y)
    pointerUp("mouse", x, y)
end

## The title, with nothing kept, at a known height of field.
func title(saved)
    viewH = 700
    data.delete(GAME_KEY)
    data.delete(SCORES_KEY)
    scores = freshScores()
    rng = Random(3)
    resumable = nil
    pointer = nil
    levelIdx = 2
    humanFirst = true
    game = newBoard()
    state = "title"
    if saved then
        game = play([4, 3])
        human = 1
        state = "play"
        saveGame()
        game = newBoard()
        state = "title"
    end
end

## A game begun from the title, with the human playing first.
func begun()
    title(false)
    newGame()
    outcome = nil
end

func run(seconds)
    for i = 1, math.floor(seconds / 0.016 + 0.5) do
        updateFrame(0.016)
    end
end

## ── The title ────────────────────────────────────────────────────────────────────────────────────────────────────────────
title(false)
var lay = titleLay()
tapRect(lay.levels[3])
assert(levelIdx == 3 and state == "title", "a level is chosen by touching it")
tapRect(lay.levels[1])
assert(levelIdx == 1)
tapRect(lay.first)
assert(not humanFirst, "who plays first is switched by touching it")
tapRect(lay.first)
assert(humanFirst)
tapRect(lay.scores)
assert(state == "title" and levelIdx == 1, "the scores are only shown")
pointerDown("mouse", 2, 2)
pointerUp("mouse", 2, 2)
assert(state == "title", "a touch on nothing does nothing")
tapRect(lay.start)
assert(state == "play" and human == 1 and levelIdx == 1 and game.count == 0, "Play begins a game at the level shown")
title(false)
humanFirst = false
tapRect(titleLay().start)
assert(state == "play" and human == 2 and thinker <> nil, "and the computer opens when it plays first")

## the keys of the title
title(false)
keyPressed("left")
assert(levelIdx == 1)
keyPressed("left")
assert(levelIdx == 1, "the levels do not wrap round")
keyPressed("right")
keyPressed("right")
keyPressed("right")
assert(levelIdx == #LEVELS)
keyPressed("f")
assert(not humanFirst)
keyPressed("up")
assert(humanFirst)
keyPressed("c")
assert(state == "title", "there is no game to go on with")
keyPressed("space")
assert(state == "play" and levelIdx == #LEVELS)
title(false)
keyPressed("return")
assert(state == "play", "Return begins a game too")

## a game to go on with
title(true)
assert(resumable <> nil and titleLay().cont <> nil, "the title offers it")
tapRect(titleLay().cont)
assert(state == "play" and game.moves.join(",") == "4,3" and humansTurn(), "and takes it up where it was")
title(true)
keyPressed("c")
assert(state == "play" and game.count == 2)
title(true)
tapRect(titleLay().start)
assert(state == "play" and game.count == 0 and resumable == nil, "a new game gives it up")

## ── Aiming and dropping ──────────────────────────────────────────────────────────────────────────────────────────────────
begun()
lay = playLay()
pointerDown("mouse", cellX(5), lay.aimY)
assert(hover == 5 and pointer <> nil and game.count == 0, "pressing aims, and drops nothing yet")
pointerMove("mouse", cellX(6), cellY(lay, 3))
assert(hover == 6, "moving over the grid aims on")
pointerUp("mouse", cellX(6), cellY(lay, 3))
assert(game.count == 1 and game.moves[1] == 6 and pointer == nil, "the disc goes where the finger lifts")
## lifting away from the grid drops nothing
begun()
lay = playLay()
pointerDown(0, cellX(2), cellY(lay, 2))
pointerUp(0, cellX(2), lay.left.y + 5)
assert(game.count == 0 and pointer == nil and hover == 2, "a finger dragged off the grid lets go of the disc")
## the identifier 0 is a finger like another
pointerDown(0, cellX(3), cellY(lay, 2))
assert(pointer <> nil and pointer.id == 0 and hover == 3, "a finger numbered 0 is followed")
pointerUp(1, cellX(3), cellY(lay, 2))
assert(pointer <> nil and game.count == 0, "another finger lifting does not drop it")
pointerDown(1, cellX(5), cellY(lay, 2))
assert(pointer.id == 0 and hover == 3, "and only one is followed at a time")
pointerUp(0, cellX(3), cellY(lay, 2))
assert(game.count == 1 and game.moves[1] == 3 and pointer == nil)
## a column that is full, a disc in the air, a turn that is not the human's
begun()
game = replay([4, 4, 4, 4, 4, 4])
lay = playLay()
pointerDown("mouse", cellX(4), lay.aimY)
pointerUp("mouse", cellX(4), lay.aimY)
assert(game.count == 6, "a full column takes nothing")
pointerDown("mouse", cellX(1), lay.aimY)
pointerUp("mouse", cellX(1), lay.aimY)
assert(game.count == 7 and fall <> nil)
pointerDown("mouse", cellX(2), lay.aimY)
pointerUp("mouse", cellX(2), lay.aimY)
assert(game.count == 7, "nothing while a disc is falling")
## a lift that was never seen: nobody holds the screen, so the next touch is heard
begun()
pointerDown(0, cellX(2), playLay().aimY)
assert(pointer <> nil)
releaseLostPointer(1, false)
assert(pointer <> nil, "a finger is down: the pointer is kept")
releaseLostPointer(0, true)
assert(pointer <> nil, "so is a mouse button")
releaseLostPointer(0, false)
assert(pointer == nil, "with neither down it is let go")
pointerDown("mouse", cellX(5), playLay().aimY)
assert(pointer <> nil and hover == 5, "and the next touch is heard")
pointerUp("mouse", cellX(5), playLay().aimY)
## the mouse moving with no button down aims
begun()
pointerMove("mouse", cellX(7), cellY(playLay(), 0))
assert(hover == 7, "the pointer over the grid aims, pressed or not")
pointerMove("mouse", 2, 2)
assert(hover == 7, "and past the grid it leaves the aim where it was")

## ── The buttons of a game ────────────────────────────────────────────────────────────────────────────────────────────────
begun()
lay = playLay()
tapRect(lay.left)
assert(game.count == 0 and state == "play", "Undo with nothing to take back does nothing")
humanDrop(4)
run(1.5)
assert(game.count == 2)
tapRect(playLay().left)
assert(game.count == 0 and humansTurn(), "Undo takes the move and the reply back")
humanDrop(4)
tapRect(playLay().right)
assert(state == "title" and resumable <> nil, "Menu leaves the game, which is kept")

## ── The end of a game ────────────────────────────────────────────────────────────────────────────────────────────────────
begun()
game = replay([1, 7, 2, 7, 3, 7])
humanDrop(4)
run(1.0)
assert(state == "over")
pointerDown("mouse", cellX(4), playLay().aimY)
pointerUp("mouse", cellX(4), playLay().aimY)
assert(game.count == 7 and pointer == nil, "nothing is dropped once the game is over")
tapRect(playLay().left)
assert(state == "play" and game.count == 0 and human == 1, "Play again begins another game, as the title said")
game = replay([1, 7, 2, 7, 3, 7])
humanDrop(4)
run(1.0)
tapRect(playLay().right)
assert(state == "title", "Menu goes back to the title")
## the keys of the end
begun()
game = replay([1, 7, 2, 7, 3, 7])
humanDrop(4)
run(1.0)
keyPressed("space")
assert(state == "play" and game.count == 0)
game = replay([1, 7, 2, 7, 3, 7])
humanDrop(4)
run(1.0)
keyPressed("escape")
assert(state == "title")

## ── The keys of a game ───────────────────────────────────────────────────────────────────────────────────────────────────
begun()
keyPressed("left")
keyPressed("left")
assert(hover == 2)
keyPressed("right")
assert(hover == 3)
for i = 1, 9 do
    keyPressed("left")
end
assert(hover == 1, "the aim stops at the edge")
keyPressed("down")
assert(game.count == 1 and game.moves[1] == 1, "down drops the disc where it is aimed")
run(1.5)
keyPressed("5")
assert(game.count >= 3 and game.moves[3] == 5 and hover == 5, "a digit aims and drops at once")
keyPressed("9")
keyPressed("0")
assert(game.count <= 4, "a digit that is no column does nothing")
run(1.5)
var n = game.count
keyPressed("u")
assert(game.count < n, "U takes a move back")
keyPressed("m")
assert(state == "title" and resumable <> nil, "M goes to the title")
begun()
keyPressed("space")
assert(game.count == 1 and game.moves[1] == 4, "space drops in the middle, where the aim starts")
keyPressed("escape")
assert(state == "title")
print("connect4 screens ok")
