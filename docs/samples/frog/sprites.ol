## The LOOK of Frog: every picture of the arcade game that the example draws, built into a texture from the digits that
## tools/convert_frog_data.py decoded (tiles.ol, arcade.ol). A picture is a string of colour indices 0..3, row after row, and
## this file says what colour each index takes on each object: the board's colour PROM is not part of what was decoded, so the
## colours are ours, chosen to read as the originals do.

import "tiles.ol"
import "arcade.ol"
import "field.ol"
import "rules.ol"

global laneImgs = []           ## per lane, its object's picture: one for a log or a car, the three poses of swimming for turtles
global frogImgs = {}           ## the frog, by the way it faces and then by "rest" or "hop"
global pics = {}               ## the other sprites, by name
global glyphs = {}             ## the letters, the digits and the dash, one picture each

const CLEAR = Color(0, 0, 0, 0)
const PALETTE = {"0": CLEAR, "1": Color(0.86, 0.2, 0.2), "2": Color(0.2, 0.8, 0.25), "3": Color(1.0, 1.0, 1.0)}
const LOG_PALETTE = {"0": CLEAR, "1": Color(0.62, 0.36, 0.14), "2": Color(0.42, 0.24, 0.08), "3": Color(0.92, 0.78, 0.52)}
const INK_PALETTE = {"0": CLEAR, "1": Color(1, 1, 1), "2": Color(1, 1, 1), "3": Color(1, 1, 1)}

## The sprites the game draws, by the number the arcade board gives them (what each one shows is in the head of
## tools/convert_frog_data.py's source page).
const SPRITE_CODES = {
    frog: 0x1E, hop: 0x1C, fly: 0x20, fly2: 0x21, crocodile: 0x34, skull: 0x3C, home: 0x3F,
    splash1: 0x22, splash2: 0x23, splash3: 0x24, titleF: 0x35, titleR: 0x36, titleO: 0x37, titleG: 0x3D
}
const GLYPH_TEXT = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-"

## The rows of a picture of w x h pixels, one string each.
func rowsOf(s, w, h)
    var rows = []
    for y = 0, h - 1 do
        rows.push(s.substr(y * w + 1, w))
    end
    return rows
end

## The same rows turned: "cw" a quarter turn clockwise, "ccw" counter-clockwise, "half" half a turn.
func turnRows(rows, how)
    var size = #rows
    var out = []
    for y = 0, size - 1 do
        var line = []
        for x = 0, size - 1 do
            var sx = x
            var sy = y
            if how == "cw" then
                sx = y
                sy = size - 1 - x
            elseif how == "ccw" then
                sx = size - 1 - y
                sy = x
            else
                sx = size - 1 - x
                sy = size - 1 - y
            end
            line.push(rows[sy + 1].char(sx + 1))
        end
        out.push(line.join(""))
    end
    return out
end

## The picture of a lane's object: its tiles in pairs, the first pair at the right-hand end (the arcade draws its strips
## that way round), a pair being the 8 pixels of one tile above the 8 of the other. `phase` picks one of the poses of
## swimming a turtle has: the pictures follow each other in the table a fixed distance apart, which is more than the tiles a
## group of turtles takes of each.
func laneRows(lane, phase)
    var rows = laneSpec(1, lane).tiles
    var codes = LANE_TILES[lane + 1]
    var base = phase * (#codes // LANE_PHASES[lane + 1])
    var out = []
    for y = 0, CELL - 1 do
        var line = []
        for x = 0, rows * TILE - 1 do
            var code = codes[base + 2 * (rows - 1 - x // TILE) + y // TILE + 1]
            line.push(TILES[code + 1].char((y % TILE) * TILE + x % TILE + 1))
        end
        out.push(line.join(""))
    end
    return out
end

func buildSprites()
    laneImgs = []
    for lane = 0, 10 do
        var imgs = []
        if lane <> 5 then
            var palette = PALETTE
            if lane == 0 or lane == 2 or lane == 3 then
                palette = LOG_PALETTE
            end
            for phase = 0, LANE_PHASES[lane + 1] - 1 do
                imgs.push(image.fromPattern(laneRows(lane, phase), palette))
            end
        end
        laneImgs.push(imgs)
    end

    pics = {}
    for name, code in SPRITE_CODES do
        pics[name] = image.fromPattern(rowsOf(SPRITES[code + 1], CELL, CELL), PALETTE)
    end

    ## The frog faces up as it is drawn; the other ways are the picture turned.
    frogImgs = {}
    for face, how in {up: "none", right: "cw", down: "half", left: "ccw"} do
        var rest = rowsOf(SPRITES[SPRITE_CODES.frog + 1], CELL, CELL)
        var hop = rowsOf(SPRITES[SPRITE_CODES.hop + 1], CELL, CELL)
        if how <> "none" then
            rest = turnRows(rest, how)
            hop = turnRows(hop, how)
        end
        frogImgs[face] = {rest: image.fromPattern(rest, PALETTE), hop: image.fromPattern(hop, PALETTE)}
    end

    ## The letters are the board's own: the digits from tile 0, the alphabet from tile 17, the dash at tile 43.
    glyphs = {}
    for i = 1, len(GLYPH_TEXT) do
        var c = GLYPH_TEXT.char(i)
        var code = i - 1
        if i > 10 and i <= 36 then
            code = 17 + i - 11
        elseif i == 37 then
            code = 43
        end
        glyphs[c] = image.fromPattern(rowsOf(TILES[code + 1], TILE, TILE), INK_PALETTE)
    end
end
