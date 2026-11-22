## What Frog looks like: the field with its lanes, the frog, what stands in the homes, the header and the foot of the screen, and
## the screens before and after a game. It only reads the state.

import "field.ol"
import "rules.ol"
import "state.ol"
import "sprites.ol"

const BLACK   = Color(0, 0, 0)
const WATER   = Color(0.0, 0.08, 0.55)
const BANK    = Color(0.42, 0.18, 0.62)         ## the strips a frog is safe on
const HEDGE   = Color(0.05, 0.45, 0.12)         ## the top of the field, around the homes
const WHITE   = Color(1, 1, 1)
const RED     = Color(0.92, 0.2, 0.2)
const YELLOW  = Color(1.0, 0.85, 0.1)
const GREEN   = Color(0.2, 0.85, 0.3)
const BAR_LOW = Color(0.95, 0.25, 0.15)

func block(col, x, y, w, h)
    graphics.noStroke()
    graphics.fill(col)
    graphics.rect(x, y, w, h)
end

## A text of the board's own 8 pixel letters, from x, y, in the colour `col`.
func drawText(str, x, y, col)
    graphics.tint(col)
    for i = 1, len(str) do
        var img = glyphs[str.char(i)]
        if img <> nil then
            graphics.sprite(img, x + (i - 1) * TILE, y, TILE, TILE)
        end
    end
    graphics.noTint()
end

func drawTextRight(str, x, y, col)
    drawText(str, x - len(str) * TILE, y, col)
end

func drawTextCentre(str, y, col)
    drawText(str, (FIELD_W - len(str) * TILE) / 2, y, col)
end

func drawBackground()
    graphics.clear(BLACK)
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
    for lane = 0, 10 do
        if lane <> 5 then
            var y = rowY(11 - lane)
            for it in laneItems(tier, lane, laneOff[lane + 1]) do
                var phase = 0
                if LANE_DIVES[lane + 1] then
                    phase = turtleFrame(clock, it.group)
                end
                if phase < 3 then
                    graphics.sprite(laneImgs[lane + 1][phase + 1], math.floor(it.x0 + 0.5), y, it.x1 - it.x0, CELL)
                end
            end
        end
    end
end

## The frogs already home, and the fly or the crocodile in an empty one.
func drawHomes()
    for h = 1, HOMES do
        if homes[h] then
            graphics.sprite(pics.home, homeX(h), rowY(ROW_HOMES), CELL, CELL)
        end
    end
    if event <> nil then
        var img = pics.fly
        if event.kind == "crocodile" then
            img = pics.crocodile
        elseif math.floor(clock * 6) % 2 == 1 then
            img = pics.fly2
        end
        graphics.sprite(img, homeX(event.home), rowY(ROW_HOMES), CELL, CELL)
    end
end

func drawFrog()
    if frog.dead == "over" then
        graphics.sprite(pics.skull, math.floor(frog.x + 0.5), rowY(frog.row), CELL, CELL)
        return
    end
    var x = frog.x
    var y = rowY(frog.row)
    var img = frogImgs[frog.face].rest
    if frog.hop <> nil then
        var p = frog.hop.t / HOP_TIME
        x = frog.hop.fromX + (frog.hop.toX - frog.hop.fromX) * p
        y = rowY(frog.hop.fromRow) + (rowY(frog.hop.toRow) - rowY(frog.hop.fromRow)) * p
        img = frogImgs[frog.face].hop
    end
    if frog.dead <> nil then
        if (frog.dead == "drown" or frog.dead == "edge" or frog.dead == "wall") and frog.deadT < 0.45 then
            img = pics["splash{1 + math.floor(frog.deadT / 0.15)}"]
        else
            img = pics.skull
        end
    end
    if frog.ready > 0 and math.floor(clock * 10) % 2 == 0 and frog.dead == nil then
        return
    end
    graphics.sprite(img, math.floor(x + 0.5), math.floor(y + 0.5), CELL, CELL)
end

## The header — the score, the best score — and the foot: the frogs left, the clock and the board.
func drawHud()
    drawText("1UP", 24, 8, WHITE)
    drawText("HI-SCORE", 88, 8, WHITE)
    drawTextRight("{score}", 56, 18, RED)
    drawTextRight("{best}", 136, 18, RED)
    for i = 1, math.max(lives - 1, 0) do
        graphics.sprite(pics.frog, 2 + (i - 1) * 9, FIELD_H - 12, 8, 8)
    end
    drawText("TIME", 120, FIELD_H - 12, YELLOW)
    var w = math.floor(timeLeft / TIME_LIMIT * 64)
    var col = GREEN
    if timeLeft < 8 then
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
    block(BLACK, 8, 88, FIELD_W - 16, 84)
    var letters = [pics.titleF, pics.titleR, pics.titleO, pics.titleG]
    for i = 1, 4 do
        graphics.sprite(letters[i], 80 + (i - 1) * 16, 100, CELL, CELL)
    end
    drawTextCentre("PRESS SPACE OR TAP", 132, WHITE)
    drawTextCentre("ARROWS OR TAP THE SIDE", 148, YELLOW)
    drawTextCentre("OF THE FROG TO HOP", 160, YELLOW)
end
