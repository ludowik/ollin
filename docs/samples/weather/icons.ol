## The pictures of the kinds of weather (the `kind` of forecast.ol): a sun, a cloud and what falls from it, drawn with
## shapes and animated by elapsedTime. The sizes are relative to `r`, about the size of the cloud or the sun.

import "../lib/draw.ol"

func drawCloud(x, y, r, shade)
    gfx.fill(shade, shade, shade, 1)
    gfx.circle(x - r * 0.55, y + r * 0.1, r * 0.5)
    gfx.circle(x + r * 0.1, y - r * 0.2, r * 0.65)
    gfx.circle(x + r * 0.65, y + r * 0.15, r * 0.45)
    gfx.rect(x - r * 0.55, y + r * 0.1, r * 1.2, r * 0.5)
end

func drawSun(x, y, r)
    gfx.stroke(1, 0.85, 0.3, 1)
    gfx.strokeSize(math.max(r * 0.12, 1))
    for i = 0, 7 do
        var a = (i / 8 + elapsedTime * 0.03) * math.TAU
        var c = math.cos(a)
        var s = math.sin(a)
        gfx.line(x + c * r * 1.25, y + s * r * 1.25, x + c * r * 1.65, y + s * r * 1.65)
    end
    gfx.noStroke()
    gfx.fill(1, 0.85, 0.3, 1)
    gfx.circle(x, y, r)
end

## The picture of a kind of weather.
func drawIcon(kind, x, y, r)
    if kind == "clear" then
        drawSun(x, y, r * 0.8)
    elseif kind == "partly" then
        drawSun(x - r * 0.45, y - r * 0.4, r * 0.55)
        drawCloud(x + r * 0.1, y + r * 0.2, r, 1)
    else
        drawCloud(x, y - r * 0.15, r, kind == "storm" and 0.55 or kind == "rain" and 0.8 or 0.97)
        gfx.stroke(0.55, 0.75, 1, 1)
        gfx.strokeSize(math.max(r * 0.07, 1))
        if kind == "rain" then
            for i = -1, 1 do
                var drift = (elapsedTime * 1.5 + i * 0.37) % 1
                gfx.line(x + i * r * 0.5 + drift * r * 0.1, y + r * 0.55 + drift * r * 0.3,
                              x + i * r * 0.5 - r * 0.08 + drift * r * 0.1, y + r * 0.8 + drift * r * 0.3)
            end
        elseif kind == "snow" then
            gfx.noStroke()
            gfx.fill(1, 1, 1, 1)
            for i = -1, 1 do
                var drift = (elapsedTime * 0.6 + i * 0.31) % 1
                gfx.circle(x + i * r * 0.5 + math.sin(elapsedTime * 2 + i) * r * 0.08, y + r * 0.5 + drift * r * 0.4, r * 0.07)
            end
        elseif kind == "fog" then
            gfx.stroke(1, 1, 1, 0.8)
            for i = 0, 2 do
                gfx.line(x - r * 0.8 + i * r * 0.15, y + r * 0.55 + i * r * 0.2, x + r * 0.8 - i * r * 0.15, y + r * 0.55 + i * r * 0.2)
            end
        elseif kind == "storm" then
            gfx.stroke(1, 0.9, 0.3, 1)
            gfx.line(x + r * 0.1, y + r * 0.4, x - r * 0.15, y + r * 0.7)
            gfx.line(x - r * 0.15, y + r * 0.7, x + r * 0.1, y + r * 0.7)
            gfx.line(x + r * 0.1, y + r * 0.7, x - r * 0.1, y + r * 1.0)
        end
        gfx.noStroke()
    end
end
