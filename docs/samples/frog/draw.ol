## What Frog looks like: the field with its lanes, the frog, what stands in the homes, the header and the foot of the screen, and
## the screens before and after a game. It only reads the state.

import "field.ol"
import "rules.ol"
import "state.ol"
import "sprites.ol"
import "../lib/arrow.ol"

const BLACK   = Color(0, 0, 0)
const WATER   = Color(0.0, 0.08, 0.55)
const BANK    = Color(0.42, 0.18, 0.62)         ## the strips a frog is safe on
const HEDGE   = Color(0.05, 0.45, 0.12)         ## the top of the field, around the homes
const WHITE   = Color(1, 1, 1)
const RED     = Color(0.92, 0.2, 0.2)
const YELLOW  = Color(1.0, 0.85, 0.1)
const GREEN   = Color(0.2, 0.85, 0.3)
const BAR_LOW = Color(0.95, 0.25, 0.15)
const KEY_FILL = Color(0.2, 0.12, 0.34)         ## the buttons under the field
const KEY_EDGE = Color(0.62, 0.48, 0.9)

const SWIM = [0, 1, 2, 1]                      ## the poses of a swimming turtle, in the order its legs move

func block(col, x, y, w, h)
    gfx.noStroke()
    gfx.fill(col)
    gfx.rect(x, y, w, h)
end

## A text of the board's own 8 pixel letters, from x, y, in the colour `col`.
func drawText(str, x, y, col)
    gfx.tint(col)
    for i = 1, len(str) do
        var img = glyphs[str.char(i)]
        if img <> nil then
            gfx.sprite(img, x + (i - 1) * TILE, y, TILE, TILE)
        end
    end
    gfx.noTint()
end

func drawTextRight(str, x, y, col)
    drawText(str, x - len(str) * TILE, y, col)
end

func drawTextCentre(str, y, col)
    drawText(str, (FIELD_W - len(str) * TILE) / 2, y, col)
end

## The strip under the field: the four ways, and pause and sound with what they do now.
func drawPad()
    gfx.segments(8)                    ## the corners are 4 pixels: the default 64 segments each would be thousands of triangles
    gfx.fill(KEY_FILL)
    gfx.stroke(KEY_EDGE)
    gfx.strokeSize(1)
    for b in buttons do
        gfx.rect(b.x, b.y, b.w, b.h, 4)
    end
    gfx.noStroke()
    gfx.fill(YELLOW)
    for b in buttons do
        if b.name <> "pause" and b.name <> "sound" then
            gfx.polygon(arrowPoints(b.name, b.x + b.w / 2, b.y + b.h / 2, math.floor(b.w / 4)))
        end
    end
    for b in buttons do
        if b.name == "pause" or b.name == "sound" then
            var label = "PAUSE"
            if b.name == "sound" then
                label = soundOn and "SOUND" or "MUTED"
            elseif paused then
                label = "RESUME"
            end
            drawText(label, b.x + (b.w - len(label) * TILE) / 2, b.y + (b.h - TILE) / 2, WHITE)
        end
    end
end

func drawBackground()
    gfx.clear(BLACK)
    block(HEDGE, 0, rowY(ROW_HOMES), FIELD_W, CELL)
    for h = 1, HOMES do
        block(WATER, homeX(h), rowY(ROW_HOMES), CELL, CELL)
    end
    block(WATER, 0, rowY(11), FIELD_W, 5 * CELL)
    block(BANK, 0, rowY(ROW_MEDIAN), FIELD_W, CELL)
    block(BANK, 0, rowY(ROW_START), FIELD_W, CELL)
end

## The objects of every lane, in the picture the arcade tables give them.
func drawLanes()
    var tier = tierOfBoard(board)
    var pose = SWIM[math.floor(clock * 4) % 4 + 1]
    for lane = 0, 10 do
        if hasObjects(lane) then
            var y = rowY(ROW_HOMES - 1 - lane)
            var dives = divesIn(lane)
            for it in laneItems(tier, lane, laneOff[lane + 1]) do
                var frame = 0
                if dives then
                    frame = turtleFrame(clock, it.group)
                end
                var x = math.floor(it.x0 + 0.5)
                if frame == 0 then
                    var imgs = laneImgs[lane + 1]
                    gfx.sprite(imgs[(dives and pose or 0) + 1], x, y, it.x1 - it.x0, CELL)
                else
                    ## a group that dives is a ring of bubbles for each turtle, the board's own picture of something sinking
                    for k = 0, (it.x1 - it.x0) // CELL - 1 do
                        gfx.sprite(splashImgs[frame], x + k * CELL, y, CELL, CELL)
                    end
                end
            end
        end
    end
end

## The frogs already home, and the fly or the crocodile in an empty one.
func drawHomes()
    for h = 1, HOMES do
        if homes[h] then
            gfx.sprite(pics.home, homeX(h), rowY(ROW_HOMES), CELL, CELL)
        end
    end
    if event <> nil then
        var img = pics.fly
        if event.kind == "crocodile" then
            img = pics.crocodile
        elseif math.floor(clock * 6) % 2 == 1 then
            img = pics.fly2
        end
        gfx.sprite(img, homeX(event.home), rowY(ROW_HOMES), CELL, CELL)
    end
end

func drawFrog()
    var x = frog.x
    var y = rowY(frog.row)
    var img = frogImgs[frog.face].rest
    if frog.hop <> nil then
        var p = hopFraction(frog.hop)
        x = hopX(frog.hop)
        y = rowY(frog.hop.fromRow) + (rowY(frog.hop.toRow) - rowY(frog.hop.fromRow)) * p
        img = frogImgs[frog.face].hop
    end
    if frog.dead <> nil then
        if DEATHS[frog.dead].splash and frog.deadT < SPLASH_TIME then
            img = splashImgs[splashFrame(frog.deadT)]
        else
            img = pics.skull
        end
    end
    if frog.ready > 0 and math.floor(clock * 10) % 2 == 0 and frog.dead == nil then
        return
    end
    gfx.sprite(img, math.floor(x + 0.5), math.floor(y + 0.5), CELL, CELL)
end

## The header — the score, the best score — and the foot: the frogs left, the clock and the board.
func drawHud()
    drawText("1UP", 24, 8, WHITE)
    drawText("HI-SCORE", 88, 8, WHITE)
    drawTextRight("{score}", 56, 18, RED)
    drawTextRight("{math.max(best, score)}", 136, 18, RED)
    for i = 1, math.max(lives - 1, 0) do
        gfx.sprite(pics.frog, 2 + (i - 1) * 9, FIELD_H - 12, 8, 8)
    end
    drawText("TIME", 120, FIELD_H - 12, YELLOW)
    var w = math.floor(timeLeft / TIME_LIMIT * 64)
    var col = GREEN
    if timeLeft < TIME_LOW then
        col = BAR_LOW
    end
    block(col, 152, FIELD_H - 11, math.max(w, 0), 6)
    drawTextRight("LEVEL {board}", FIELD_W - 2, FIELD_H - 22, WHITE)
end

func drawPlay()
    drawBackground()
    drawLanes()
    drawHomes()
    drawFrog()
    drawHud()
    drawPad()
    if banner <> nil then
        drawTextCentre(banner.text, 120, YELLOW)
    end
    if paused then
        drawTextCentre("PAUSED", 120, YELLOW)
    end
    if state == "over" then
        drawTextCentre("GAME OVER", 112, RED)
        drawTextCentre("PRESS SPACE", 128, WHITE)
    end
end

func drawTitle()
    drawBackground()
    drawLanes()
    drawHud()
    drawPad()
    block(BLACK, 8, 88, FIELD_W - 16, 84)
    for i = 1, 4 do
        gfx.sprite(titleImgs[i], 80 + (i - 1) * 16, 100, CELL, CELL)
    end
    drawTextCentre("PRESS SPACE OR TAP", 132, WHITE)
    drawTextCentre("ARROWS OR THE BUTTONS", 148, YELLOW)
    drawTextCentre("BELOW TO HOP", 160, YELLOW)
end
