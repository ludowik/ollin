## The places of Tetris (docs/samples/tetris/places.ol): that the well, the cards and the next piece fit on the screen
## of 160 by 144 points without touching each other.

import "places.ol"

func inside(r)
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= SCREEN.w and r.y + r.h <= SCREEN.h and r.w > 0 and r.h > 0
end

func apart(a, b)
    return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

var cards = [SCORE_CARD, LEVEL_CARD, LINES_CARD, NEXT_CARD]
assert(SCREEN.w == 160 and SCREEN.h == 144 and SCREEN.h % 6 == 0, "the wall of bricks repeats every 6 rows")
assert(WELL.w == COLS * CELL and WELL.h == ROWS * CELL and WELL.h == SCREEN.h, "the well is 10 by 18 cells and the height of the screen")
assert(inside(WELL))
for r in cards do
    assert(inside(r))
    assert(apart(r, WELL))
    assert(r.x >= WELL.x + WELL.w + 8, "a card is on the wall of bricks")
end
for i = 1, 4 do
    for j = i + 1, 4 do
        assert(apart(cards[i], cards[j]), "cards {i} and {j} overlap")
    end
end

## The wall of bricks, 8 points wide, stands each side of the well.
assert(WELL.x >= 8 + 1 and WELL.x + WELL.w + 8 < SCREEN.w)

## The cards are one column, from the top down: score, level, lines, the next piece.
assert(LEVEL_CARD.x == SCORE_CARD.x and LINES_CARD.x == SCORE_CARD.x and LEVEL_CARD.w == SCORE_CARD.w and LINES_CARD.w == SCORE_CARD.w)
assert(SCORE_CARD.y < LEVEL_CARD.y and LEVEL_CARD.y < LINES_CARD.y and LINES_CARD.y < NEXT_CARD.y)
assert(NEXT_CARD.y + NEXT_CARD.h <= SCREEN.h)

## The 4 by 4 cells of the next piece are inside its card, with room for its frame.
assert(NEXT_GRID.x - NEXT_CARD.x >= 4 and NEXT_GRID.y - NEXT_CARD.y >= 4)
assert(NEXT_CARD.x + NEXT_CARD.w - (NEXT_GRID.x + 4 * CELL) >= 4 and NEXT_CARD.y + NEXT_CARD.h - (NEXT_GRID.y + 4 * CELL) >= 4)

print("tetris places ok")
