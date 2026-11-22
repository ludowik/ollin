## Where things are on Connect Four's screen (docs/samples/connect4/layout.ol): how tall the field is, that everything is inside it, that
## nothing a finger has to hit overlaps another thing or is too small, and which column a point is over.

import "layout.ol"

assert(viewHeight(400, 800) == VIEW_MAX and viewHeight(390, 844) == VIEW_MAX, "a tall screen gets a tall field")
assert(viewHeight(1000, 500) == VIEW_MIN and viewHeight(400, 5000) == VIEW_MAX and viewHeight(400, 640) == 640, "within bounds, as tall as the shape asks")
assert(playHeight() <= VIEW_MIN, "the game's screen fits the smallest field: {playHeight()}")

## a rectangle is in the field, and a point is in a rectangle
func inside(r, viewH)
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= VIEW_W and r.y + r.h <= viewH
end

func apart(a, b)
    return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

for viewH = VIEW_MIN, VIEW_MAX, 50 do
    var lay = playLayout(viewH)
    assert(inside(lay.panel, viewH) and inside(lay.left, viewH) and inside(lay.right, viewH), "{viewH}: the grid and the buttons are in the field")
    assert(lay.headerY >= 0 and lay.aimTop > lay.headerY and lay.aimY > lay.aimTop and lay.panel.y >= lay.aimTop + AIM_H, "{viewH}: from the top down: header, aim, grid")
    assert(lay.statusY > lay.panel.y + lay.panel.h and lay.left.y > lay.statusY, "{viewH}: the status line is between the grid and the buttons")
    assert(apart(lay.left, lay.right) and apart(lay.left, lay.panel) and apart(lay.right, lay.panel), "{viewH}: nothing overlaps")
    assert(lay.left.h >= 44 and lay.left.w >= 44 and lay.right.w >= 44, "{viewH}: a button is big enough for a finger")
    assert(lay.left.y + lay.left.h <= viewH - MARGIN // 2, "{viewH}: and leaves room under it")
    ## the squares are in the grid
    for col = 1, COLS do
        for row = 0, ROWS - 1 do
            var x = cellX(col)
            var y = cellY(lay, row)
            assert(inRect(x, y, lay.panel) and x - CELL / 2 >= lay.panel.x and y + CELL / 2 <= lay.panel.y + lay.panel.h, "{viewH}: square {col},{row} is in the grid")
        end
    end
    assert(cellY(lay, 0) > cellY(lay, ROWS - 1) and cellX(1) < cellX(COLS), "row 0 is at the bottom, column 1 on the left")
    ## which column a point is over
    for col = 1, COLS do
        assert(columnAt(cellX(col)) == col, "{viewH}: the middle of column {col}")
        assert(columnAt(cellX(col) - CELL / 2 + 1) == col and columnAt(cellX(col) + CELL / 2 - 1) == col, "{viewH}: and its edges")
        assert(inBoardZone(lay, cellX(col), lay.aimY) and inBoardZone(lay, cellX(col), cellY(lay, 0)), "{viewH}: above and in the grid is the board zone")
    end
    assert(columnAt(3) == nil and columnAt(VIEW_W - 3) == nil, "{viewH}: past the grid there is no column")
    assert(columnAt(lay.panel.x + 2) == 1 and columnAt(lay.panel.x + lay.panel.w - 2) == COLS, "{viewH}: the blue border belongs to the column next to it")
    assert(not inBoardZone(lay, cellX(4), lay.headerY + 5) and not inBoardZone(lay, cellX(4), lay.left.y + 5), "{viewH}: the header and the buttons are not the board")
    assert(rectAt([lay.left, lay.right], lay.left.x + 5, lay.left.y + 5) == lay.left and rectAt([lay.left, lay.right], lay.right.x + 5, lay.right.y + 5) == lay.right)
end

## the title, with and without a game to go on with
for viewH = VIEW_MIN, VIEW_MAX, 100 do
    for saved in [false, true] do
        var lay = titleLayout(viewH, 3, saved)
        var all = [lay.first, lay.scores, lay.start]
        for r in lay.levels do
            all.push(r)
        end
        if saved then
            all.push(lay.cont)
        end
        assert(#lay.levels == 3 and (lay.cont <> nil) == saved, "{viewH}: a button for each level, and for going on only when there is a game")
        for r in all do
            assert(inside(r, viewH), "{viewH}: the title's rectangles are in the field")
        end
        for i = 1, #all do
            for j = i + 1, #all do
                assert(apart(all[i], all[j]), "{viewH}: the title's rectangles do not overlap")
            end
        end
        for r in [lay.first, lay.start].concat(lay.levels) do
            assert(r.h >= 44 and r.w >= 44, "{viewH}: a button is big enough for a finger")
        end
        assert(lay.titleY < lay.subtitleY and lay.subtitleY < lay.levels[1].y and lay.scores.y > lay.first.y, "{viewH}: in the order they are read")
    end
end
assert(titleLayout(VIEW_MIN, 3, true).start.y > titleLayout(VIEW_MIN, 3, true).cont.y, "the game in progress is offered before a new one")
print("connect4 layout ok")
