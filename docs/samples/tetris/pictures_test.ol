## The pictures of Tetris (docs/samples/tetris/pictures.ol): how a picture becomes rectangles, the shape of every
## picture, and the screen of a game against a screenshot of the handheld (the points quoted below are read off it).

import "pictures.ol"

## The picture that rectangles paint, as rows of text with '_' where nothing is painted. Rectangles that overlap are
## refused unless `overlap` allows them: a picture never paints a point twice, the screen paints over itself.
func paint(rects, w, h, overlap)
    var shades = [" ", ".", "+", "#"]
    var grid = []
    for j = 1, h do
        var row = []
        for i = 1, w do
            row.push("_")
        end
        grid.push(row)
    end
    for r in rects do
        assert(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= w and r[2] + r[4] <= h, "a rectangle outside the picture")
        for y = r[2] + 1, r[2] + r[4] do
            for x = r[1] + 1, r[1] + r[3] do
                assert(overlap or grid[y][x] == "_", "two rectangles paint the point {x - 1}, {y - 1}")
                grid[y][x] = shades[r[5]]
            end
        end
    end
    var rows = []
    for row in grid do
        rows.push(row.join(""))
    end
    return rows
end

## The rectangles of a picture paint that picture, nothing more, nothing less.
func roundTrip(name, rows)
    var painted = paint(pictureRects(rows), len(rows[1]), len(rows), false)
    for j = 1, len(rows) do
        assert(painted[j] == rows[j], "{name}, row {j}: {rows[j]} painted as {painted[j]}")
    end
end

## Runs of one green become one rectangle, and the same run in the rows below makes it taller.
var merged = pictureRects(["##", "##"])
assert(len(merged) == 1 and merged[1][1] == 0 and merged[1][2] == 0 and merged[1][3] == 2 and merged[1][4] == 2)
assert(merged[1][5] == 4)
assert(len(pictureRects(["#_#", "#_#"])) == 2)
assert(len(pictureRects(["#.", ".#"])) == 4)
assert(len(pictureRects(["#_", "__"])) == 1)
assert(len(pictureRects(WALL_ROWS)) == 10)
assert(inkOf("?") == 0 and inkOf("_") == 0)

for name, rows in BLOCK_ROWS do
    assert(len(rows) == 8, "block {name}")
    for row in rows do
        assert(len(row) == 8, "block {name}: {row}")
    end
    roundTrip("block " + name, rows)
end

## A block of a piece is painted in the four greens of the screen and every point of it is painted.
for name, rows in BLOCK_ROWS do
    var painted = paint(pictureRects(rows), 8, 8, false)
    for row in painted do
        assert(row.find("_") == nil or row.find("_") == 0, "block {name} leaves a point unpainted: {row}")
    end
end

## The long piece: the sides it has are dark, and the cells the handheld shows are the sets of sides they must be.
for sides = 0, 15 do
    var rows = STIPPLE_ROWS["{sides}"] or stippleRows(STIPPLE_DOTS, sides)
    assert(len(rows) == 8, "stipple {sides}")
    for row in rows do
        assert(len(row) == 8)
    end
    roundTrip("stipple {sides}", rows)
    var left = ""
    var right = ""
    for row in rows do
        left = left + row.char(1)
        right = right + row.char(8)
    end
    assert((left == "########") == ((sides & 1) <> 0), "stipple {sides}: the left edge")
    assert((right == "########") == ((sides & 2) <> 0), "stipple {sides}: the right edge")
    assert((rows[1] == "########") == ((sides & 4) <> 0), "stipple {sides}: the top edge")
    assert((rows[8] == "########") == ((sides & 8) <> 0), "stipple {sides}: the bottom edge")
end
assert(len(STIPPLE_ROWS) == 6)

## The letters and the digits: 6 by 6, ink and nothing else.
var font = {}
for ch, rows in FONT_ROWS do
    assert(len(rows) == 6, "glyph {ch}")
    for row in rows do
        assert(len(row) == 6, "glyph {ch}: {row}")
        for i = 1, 6 do
            assert(row.char(i) == "#" or row.char(i) == "_", "glyph {ch}: {row}")
        end
    end
    font[ch] = pictureRects(rows)
end
for ch in ["S", "C", "O", "R", "E", "L", "V", "I", "N", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    assert(font[ch] <> nil, "no glyph for {ch}")
end

## A text is its glyphs on a pitch of 8; a character with no glyph is a blank of that pitch.
var one = textRects(font, "L")
var two = textRects(font, "LL")
assert(len(two) == 2 * len(one))
for k = 1, len(one) do
    assert(two[len(one) + k][1] == one[k][1] + 8 and two[len(one) + k][2] == one[k][2])
end
assert(len(textRects(font, "?L")) == len(one) and textRects(font, "?L")[1][1] == 8)

## The frames: each is the same corner turned over four times, so a box reads the same from either side.
for size in [[46, 14], [46, 22], [42, 42]] do
    var corner = size[1] == 42 and NEXT_CORNER or PANEL_CORNER
    var rings = size[1] == 42 and ". +#" or " +"
    var rows = boxRows(size[1], size[2], corner, rings, " ")
    assert(len(rows) == size[2])
    for j = 1, size[2] do
        assert(len(rows[j]) == size[1])
        assert(rows[j] == rows[size[2] + 1 - j], "box {size[1]}x{size[2]} is not the same upside down, row {j}")
        for i = 1, size[1] do
            assert(rows[j].char(i) == rows[j].char(size[1] + 1 - i), "box {size[1]}x{size[2]} is not the same back to front")
        end
    end
    roundTrip("box {size[1]}x{size[2]}", rows)
end

## The screen of a game, against the screenshot of the handheld: the points quoted are x, y and a row of text read off
## it, starting at that point.
var art = paint(screenArt(font), 160, 144, true)
for row in art do
    assert(row.find("_") == nil or row.find("_") == 0, "the screen leaves a point unpainted")
end

func shows(x, y, text)
    assert(art[y + 1].substr(x + 1, len(text)) == text, "at {x}, {y}: {art[y + 1].substr(x + 1, len(text))} instead of {text}")
end

## The wall of bricks, in the two places it stands and again a few courses down (it repeats every 6 rows).
for x in [8, 96] do
    for y in [0, 48, 132] do
        shows(x, y, ".# ..# .")
        shows(x, y + 1, ".#...#..")
        shows(x, y + 2, "########")
        shows(x, y + 3, " ..# ..#")
        shows(x, y + 4, "...#...#")
        shows(x, y + 5, "########")
    end
end
shows(0, 70, "####### ")                       ## the dark strip and the light line at the left
shows(104, 70, " ####")                        ## the light line at the edge of the panel
shows(16, 70, "                ")               ## the well is the lightest green

## The score box, its corner at the top left.
shows(105, 5, "#####   ")
shows(105, 6, "####  ++")
shows(105, 7, "#### ++ ")
shows(105, 8, "#### +  ")
shows(104, 13, "      ")                        ## the light line across the panel
shows(153, 13, "+      ")                      ## and to its right edge
shows(105, 14, "++++")                          ## the ribbon, at the sides of the box
shows(105, 19, "+++++++++++++++++++++++++++++++++++++++++++++++++++++++")
shows(104, 21, "                                                        ")
shows(104, 22, " +++++")
shows(104, 33, " +++++")
shows(104, 35, " ####")
shows(150, 33, "++++++++++")                    ## the ribbon runs to the right edge of the screen
shows(150, 22, "++++++++++")

## The boxes of the level and of the lines: the same corner, 40 and 24 rows under the score box's (its own is 14 high).
shows(105, 45, "#####   ")
shows(105, 46, "####  ++")
shows(105, 66, "#####   ")
shows(105, 67, "########")
shows(105, 69, "#####   ")
shows(105, 70, "####  ++")
shows(105, 90, "#####   ")
shows(105, 91, "########")
shows(105, 18, "+++++   ")

## The first S of SCORE, in its place in the box.
shows(113, 9, " #### ")
shows(113, 10, "##    ")
shows(113, 14, " #### ")

## The words of the level and of the lines: the L stands 6 rows high, from the 4th row of its box.
for y in [49, 73] do
    shows(113, y - 1, "      ")
    shows(113, y, "##    ")
    shows(113, y + 4, "##    ")
    shows(113, y + 5, "######")
    shows(113, y + 6, "      ")
end

## The box of the next piece, its corner and its right edge.
shows(112, 99, "#####.....")
shows(112, 100, "####.     ")
shows(112, 101, "###.  .+++")
shows(112, 102, "###. .+###")
shows(112, 103, "###. +#   ")
shows(140, 103, "             #+ .###")
shows(112, 140, "#####.....")

print("tetris pictures ok")
