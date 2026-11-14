## Polygon spirals: a pen drawing of a plain cut into cells, each filled with an angular spiral of lines the same distance
## apart. The cells come from a scatter of random seeds, so no two drawings are alike; the pen then lays them one after the
## other, outwards from where it began. The geometry is in geometry.ol.

import "../lib/area.ol"
import "geometry.ol"

const PAPER = Color(0.93, 0.92, 0.88)
const INK = Color(0.06, 0.06, 0.08)
const CELL = 0.17         ## the width of a cell, in sizes of the area
const SPACING = 0.012     ## the distance between two lines of a spiral
const PEN_SPEED = 8       ## sizes of the area per second
const WAIT = 0.3          ## seconds before a press can start another drawing: a tap arrives as a touch and as a mouse press

global art = nil          ## the drawing: {segments, ends}
global shown = 0          ## how many segments are done
global penLength = 0.0    ## the length of ink laid so far
global area = {w: -1, h: -1}
global lastStart = -1.0

func begin()
    art = drawing(W, H, SIZE * CELL, SIZE * SPACING)
    shown = 0
    penLength = 0.0
    lastStart = elapsedTime
end

func restart()
    if elapsedTime - lastStart >= WAIT then
        begin()
    end
end

func setup()
    graphics.canvas(W, H, "Polygon spirals")
    graphics.fitArea()
end

func update(dt)
    if areaChanged(area) then
        begin()
    end
    penLength += SIZE * PEN_SPEED * dt
    while shown < #art.ends and art.ends[shown + 1] <= penLength do
        shown += 1
    end
end

func draw()
    graphics.clear(PAPER)
    graphics.stroke(INK)
    graphics.strokeSize(math.max(1.5, SIZE * 0.0028))
    var segments = art.segments
    for i = 1, shown do
        var s = segments[i]
        graphics.line(s[1], s[2], s[3], s[4])
    end
    if shown < #segments then
        var s = segments[shown + 1]
        var length = math.hypot(s[3] - s[1], s[4] - s[2])
        var done = (penLength - (art.ends[shown + 1] - length)) / length
        if done > 0 then
            graphics.line(s[1], s[2], math.lerp(s[1], s[3], done), math.lerp(s[2], s[4], done))
        end
    end
end

func mouse.pressed(x, y)
    restart()
end

func touch.began(id, x, y)
    restart()
end

func keyboard.keypressed(key)
    restart()
end
