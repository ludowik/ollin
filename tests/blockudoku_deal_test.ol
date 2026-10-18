## How Blockudoku draws a hand as the score rises (docs/samples/blockudoku/deal.ol): the level, the weights of the
## shapes, the aids of the early levels, and the guarantee that a hand can always be played.

import "../docs/samples/blockudoku/board.ol"
import "../docs/samples/blockudoku/pieces.ol"
import "../docs/samples/blockudoku/deal.ol"

buildShapes()

## The level is the score divided by 1000, and never goes down as the score goes up.
assert(levelOf(0) == 0 and levelOf(999) == 0 and levelOf(1000) == 1 and levelOf(7999) == 7 and levelOf(13000) == 13)
var last = 0
for score = 0, 20000, 50 do
    assert(levelOf(score) >= last, "the level goes down at {score}")
    last = levelOf(score)
end

## The help is whole at level 0 and gone at helpEnd; the hard shapes only count after it, up to hardEnd.
assert(helpAt(0) == 1 and helpAt(8) == 0 and helpAt(20) == 0 and math.abs(helpAt(4) - 0.5) < 0.0001)
assert(hardAt(0) == 0 and hardAt(8) == 0 and hardAt(13) == 1 and hardAt(40) == 1)

var single = shapeFromKey("#")
var domino = shapeFromKey("##")
var plus = shapeFromKey(".#./###/.#.")
var line5 = shapeFromKey("#####")
assert(single.hardness == SOFT and domino.hardness == SOFT and plus.hardness == HARD and line5.hardness == HARD)
assert(shapeWeight(domino, 0) > shapeWeight(domino, 8) and shapeWeight(domino, 8) > shapeWeight(domino, 13), "a soft shape gets rarer with the level")
assert(shapeWeight(plus, 0) < shapeWeight(plus, 8) and shapeWeight(plus, 8) < shapeWeight(plus, 13), "a hard shape gets commoner with the level")
assert(shapeWeight(shapeFromKey("####"), 0) == shapeFromKey("####").weight, "a normal shape keeps its weight")
assert(shapeWeight(plus, 13) == shapeWeight(plus, 30), "past hardEnd the draw does not change")

## Over many draws the soft shapes lead at level 0 and the hard ones at level 13.
func share(level, hardness)
    var n = 0
    for i = 1, 4000 do
        if randomShape(level).hardness == hardness then
            n += 1
        end
    end
    return n
end
assert(share(0, SOFT) > share(8, SOFT) + 400 and share(13, SOFT) + 400 < share(8, SOFT), "the soft shapes by level")
assert(share(0, HARD) + 400 < share(8, HARD) and share(8, HARD) + 400 < share(13, HARD), "the hard shapes by level")

## A grid with a single hole: the single cell is the one piece that clears something, and only it fits.
var hole = boardNew()
for i = 1, CELLS do
    hole[i] = 1
end
hole[boardIdx(5, 5)] = 0
var completing = boardCompleting(hole, pieces.shapes)
assert(len(completing) == 1 and completing[1] == single, "one hole is filled by the single cell alone: {len(completing)}")
assert(len(boardCompleting(boardNew(), pieces.shapes)) == 0, "an empty grid has nothing to complete")
var rowGap = boardNew()
for c = 1, 8 do
    rowGap[boardIdx(3, c)] = 1
end
var cells = {}
for s in boardCompleting(rowGap, pieces.shapes) do
    cells[s.key] = true
end
assert(cells["#"] and cells["#/#"] and cells["#/#/#"] and not cells["##"], "a row short of its last cell: a horizontal domino cannot fill it")
assert(boardFilled(hole) == CELLS - 1 and boardFilled(boardNew()) == 0)

## A hand is played to the end when its pieces can be placed one after the other.
var two = boardNew()
for i = 1, CELLS do
    two[i] = 1
end
two[boardIdx(1, 1)] = 0
two[boardIdx(9, 9)] = 0
assert(boardPlayAll(two, [single, single]), "two single cells fit two holes")
assert(not boardPlayAll(two, [single, single, single]), "three single cells do not fit two holes")
assert(not boardPlayAll(two, [domino]), "a domino fits no isolated hole")
assert(boardPlayAll(boardNew(), [plus, line5, domino]), "three pieces fit an empty grid")
assert(boardPlayAll(boardNew(), []), "an empty hand is played")

## At level 0, on an empty grid, every hand can be played to the end.
for i = 1, 150 do
    var hand = drawHand(boardNew(), 0)
    assert(len(hand) == 3 and boardPlayAll(boardNew(), hand), "hand {i} cannot be played to the end")
end

## On a grid with one hole, the help keeps the piece that clears it in every hand, at level 0 ...
func holds(hand, shape)
    for s in hand do
        if s == shape then
            return true
        end
    end
    return false
end
for i = 1, 100 do
    var hand = drawHand(hole, 0)
    assert(holds(hand, single), "the hand {i} of level 0 has no piece that clears the hole")
    assert(fitsSomewhere(hole, hand))
end
## The same on a grid that is far from full, so that no small piece is given: only the help brings a piece that fills
## the row, and it is there in every hand of level 0, but not in every hand once the help is over.
var cleared = boardCompleting(rowGap, pieces.shapes)
func clearsRow(hand)
    for s in hand do
        if cleared.contains(s) then
            return true
        end
    end
    return false
end
var early = 0
var late = 0
for i = 1, 200 do
    if clearsRow(drawHand(rowGap, 0)) then
        early += 1
    end
    if clearsRow(drawHand(rowGap, 8)) then
        late += 1
    end
end
assert(early == 200, "level 0: {early} hands out of 200 hold a piece that fills the row")
assert(late < 200, "level 8: every hand holds a piece that fills the row")
## ... and a nearly full grid is given a small piece, which is not the case once the help is over.
var crowded = boardNew()
for i = 1, 70 do
    crowded[i] = 1
end
var withSmall = 0
var withSmallLate = 0
for i = 1, 200 do
    if hasSmall(drawHand(crowded, 0)) then
        withSmall += 1
    end
    if hasSmall(drawHand(crowded, 8)) then
        withSmallLate += 1
    end
end
assert(withSmall == 200, "a crowded grid at level 0: {withSmall} hands with a small piece out of 200")
assert(withSmallLate < 200, "past the help a small piece is not always given")

## Whatever the level, a hand always has a piece that fits when the grid allows one (the rule of the game before levels).
var scattered = boardNew()
for i = 1, CELLS do
    if i % 3 <> 0 then
        scattered[i] = 1
    end
end
for level in [0, 3, 8, 13, 25] do
    for i = 1, 60 do
        var hand = drawHand(scattered, level)
        assert(len(hand) == 3 and fitsSomewhere(scattered, hand), "level {level}: no piece of the hand fits")
    end
end
print("blockudoku deal ok")
