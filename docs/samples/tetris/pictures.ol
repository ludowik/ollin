## The pictures of the handheld's screen, with no drawing: how a picture written as rows of text becomes the
## rectangles that paint it, the data of the pictures (the blocks of the pieces, the letters and digits, the wall of
## bricks, the corners of the frames), and the screen of a game that never changes. style_gb.ol paints the rectangles;
## pictures_test.ol checks the pictures against a screenshot of the handheld.
##
## A picture is rows of text, one character a point: ' ' is the lightest green, '.' the next, '+' the next and '#' the
## darkest, and '_' leaves the point as it is. A rectangle is {x, y, w, h, shade}, the shade from 1 (lightest) to 4.

func inkOf(ch)
    if ch == " " then
        return 1
    elseif ch == "." then
        return 2
    elseif ch == "+" then
        return 3
    elseif ch == "#" then
        return 4
    end
    return 0
end

## The rectangles that paint a picture: a run of one green is one rectangle, and the same run in the rows below makes
## it taller, so that a picture costs few rectangles.
func pictureRects(rows)
    var out = []
    var open = {}
    for j = 1, len(rows) do
        var row = rows[j]
        var n = len(row)
        var fresh = {}
        var i = 1
        while i <= n do
            var ch = row.char(i)
            var shade = inkOf(ch)
            var k = i
            while k < n and row.char(k + 1) == ch do
                k += 1
            end
            if shade > 0 then
                var key = "{i},{k},{shade}"
                var rect = open[key]
                if rect then
                    rect[4] += 1
                else
                    rect = [i - 1, j - 1, k - i + 1, 1, shade]
                    out.push(rect)
                end
                fresh[key] = rect
            end
            i = k + 1
        end
        open = fresh
    end
    return out
end

## The rows of a framed box: its four corners are the same `corner` picture turned over, and between them the frame is
## `rings`, one character a point from the outside in, with `inside` in the middle.
func boxRows(w, h, corner, rings, inside)
    var n = len(corner)
    var rows = []
    for j = 0, h - 1 do
        var jj = math.min(j, h - 1 - j)
        var row = ""
        for i = 0, w - 1 do
            var ii = math.min(i, w - 1 - i)
            var ch = inside
            if ii < n and jj < n then
                ch = corner[jj + 1].char(ii + 1)
            elseif math.min(ii, jj) < len(rings) then
                ch = rings.char(math.min(ii, jj) + 1)
            end
            row = row + ch
        end
        rows.push(row)
    end
    return rows
end

## The block of the long piece, a stipple, with a dark edge on the sides given: 1 left, 2 right, 4 top, 8 bottom.
func stippleRows(dots, sides)
    var rows = []
    for j = 1, 8 do
        var row = ""
        for i = 1, 8 do
            var ch = "."
            if i > 1 and i < 8 then
                ch = dots[j].char(i - 1)
            end
            if (i == 1 and (sides & 1) <> 0) or (i == 8 and (sides & 2) <> 0) then
                ch = "#"
            end
            if (j == 1 and (sides & 4) <> 0) or (j == 8 and (sides & 8) <> 0) then
                ch = "#"
            end
            row = row + ch
        end
        rows.push(row)
    end
    return rows
end

## ── The data ───────────────────────────────────────────────────────────────────────────────────────

## The dots of the long piece, and the six cells the handheld shows of it with its own dots: a bar standing (its top,
## a middle, its bottom) and a bar lying (its left end, a middle, its right end), by the sides they have.
const STIPPLE_DOTS = ["..+..+", "+.....", "...+.+", ".+....", ".....+", "+.+...", "....+.", ".+...."]
const STIPPLE_ROWS = {
    "7": ["########", "#...+..#", "#.+...+#", "#......#", "#+..+..#", "#.....+#", "#.+.+..#", "#......#"],
    "3": ["#..+..+#", "#+.....#", "#...+.+#", "#.+....#", "#.....+#", "#+.+...#", "#....+.#", "#.+....#"],
    "11": ["#.....+#", "#..+...#", "#+...+.#", "#..+...#", "#+....+#", "#...+..#", "#.+....#", "########"],
    "13": ["########", "#.+..+..", "#.......", "#+..+.+.", "#.......", "#.+...+.", "#...+...", "########"],
    "12": ["########", "+.+.+...", "......+.", "..+.....", "+....+..", "...+...+", ".+...+..", "########"],
    "14": ["########", "+...+..#", "..+....#", ".....+.#", ".+.+...#", "......+#", "..+.+..#", "########"]
}

## The blocks of the other pieces, 8 by 8 points. The shades are told apart by their pattern as well as by their
## darkness, as on the handheld. The screenshot shows T, S, Z, O and J; L is not in it and is made up.
const BLOCK_ROWS = {
    O: ["########", "#      #", "# #### #", "# #### #", "# #### #", "# #### #", "#      #", "########"],
    T: ["########", "#......#", "#.    .#", "#. ..#.#", "#. ..#.#", "#.####.#", "#......#", "########"],
    S: ["########", "#++++++#", "#+####+#", "#+#  #+#", "#+#  #+#", "#+####+#", "#++++++#", "########"],
    Z: ["########", "#......#", "#......#", "#..##..#", "#..##..#", "#......#", "#......#", "########"],
    J: ["########", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "########"],
    L: ["########", "#++++++#", "#++  ++#", "#+    +#", "#+    +#", "#++  ++#", "#++++++#", "########"]
}

## The handheld's letters and digits, 6 points wide and 6 high on a pitch of 8; '#' is ink, '_' is not. The letters
## of the panel and the digits 6, 2, 9 and 3 are the handheld's; the other digits are made up in the same hand.
const FONT_ROWS = {
    "S": ["_####_", "##____", "_####_", "___###", "#__###", "_####_"],
    "C": ["_####_", "##__##", "##____", "##____", "##__##", "_####_"],
    "O": ["_####_", "##__##", "##__##", "##__##", "##__##", "_####_"],
    "R": ["#####_", "##__##", "##__##", "#####_", "##_#__", "##__##"],
    "E": ["######", "##____", "#####_", "##____", "##____", "######"],
    "L": ["##____", "##____", "##____", "##____", "##____", "######"],
    "V": ["#___##", "#___##", "#___##", "#___##", "_#_##_", "__##__"],
    "I": ["_####_", "__##__", "__##__", "__##__", "__##__", "_####_"],
    "N": ["#___##", "##__##", "###_##", "#_####", "#__###", "#___##"],
    "0": ["_####_", "##__##", "##__##", "##__##", "##__##", "_####_"],
    "1": ["__##__", "_###__", "__##__", "__##__", "__##__", "_####_"],
    "2": ["_####_", "#__###", "___###", "_####_", "###___", "######"],
    "3": ["#####_", "___###", "_####_", "___###", "___###", "#####_"],
    "4": ["___##_", "__###_", "_#_##_", "#__##_", "######", "___##_"],
    "5": ["######", "##____", "#####_", "___###", "#__###", "_####_"],
    "6": ["_####_", "##____", "#####_", "##__##", "##__##", "_####_"],
    "7": ["######", "____##", "___##_", "__##__", "_##___", "_##___"],
    "8": ["_####_", "##__##", "_####_", "##__##", "##__##", "_####_"],
    "9": ["_####_", "#__###", "#__###", "_#####", "___###", "_####_"]
}

## The wall of bricks: 8 points wide, 6 high, drawn over a ground of '.', so that only the joints and the lightest points
## are in it.
const WALL_ROWS = ["_# __# _", "_#___#__", "########", " __# __#", "___#___#", "########"]

## The corners of the frames of the panel: the boxes with a light and a mid-dark line, and the box of the next piece.
const PANEL_CORNER = ["_   ", "  ++", " ++ ", " +  "]
const NEXT_CORNER = ["__...", "_.   ", ".  .+", ". .+#", ". +# "]

## ── Putting them together ──────────────────────────────────────────────────────────────────────────

func addPicture(art, rects, ox, oy)
    for r in rects do
        art.push([ox + r[1], oy + r[2], r[3], r[4], r[5]])
    end
end

## The rectangles of a text in a font (a map from a character to the rectangles of its glyph).
func textRects(font, str)
    var out = []
    for i = 1, len(str) do
        var glyph = font[str.char(i)]
        if glyph then
            addPicture(out, glyph, (i - 1) * 8, 0)
        end
    end
    return out
end

## What the screen of a game shows whatever happens, in the order it is painted: the wall of bricks, the well, and
## the panel with its frames and its three words. The panel is a dark ground with a light line at its edge, boxes
## framed in a light and a mid-dark line, a ribbon of the same behind the score, and the box of the next piece,
## framed in four greens.
func addWall(art, wall, x)
    art.push([x, 0, 8, 144, 2])
    for t = 0, 23 do
        addPicture(art, wall, x, t * 6)
    end
end

func screenArt(font)
    var art = []
    var wall = pictureRects(WALL_ROWS)
    var tall = pictureRects(boxRows(46, 22, PANEL_CORNER, " +", " "))
    art.push([0, 0, 160, 144, 4])
    art.push([7, 0, 1, 144, 1])
    addWall(art, wall, 8)
    art.push([16, 0, 80, 144, 1])
    addWall(art, wall, 96)
    art.push([104, 0, 1, 144, 1])
    art.push([104, 13, 56, 1, 1])
    art.push([105, 14, 55, 7, 3])
    art.push([104, 21, 56, 14, 1])
    art.push([105, 22, 55, 1, 3])
    art.push([105, 33, 55, 1, 3])
    addPicture(art, pictureRects(boxRows(46, 14, PANEL_CORNER, " +", " ")), 109, 5)
    addPicture(art, tall, 109, 45)
    addPicture(art, tall, 109, 69)
    addPicture(art, pictureRects(boxRows(42, 42, NEXT_CORNER, ". +#", " ")), 115, 99)
    addPicture(art, textRects(font, "SCORE"), 113, 9)
    addPicture(art, textRects(font, "LEVEL"), 113, 49)
    addPicture(art, textRects(font, "LINES"), 113, 73)
    return art
end
