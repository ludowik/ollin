## The 2D graphics module for real: styles and modes, the shape primitives, text, transforms, blending
## and the viewport. It needs a window, so it runs under Xvfb with the raylib build (tests/run_gfx.sh);
## the headless build has no `graphics` (nil). The frames are screenshots read back with image.load, so
## what is checked is what reached the screen, with the smoothing off to keep the edges exact.

const SHOT_A = "/tmp/ollin_gfx_graphics_a.png"
const SHOT_B = "/tmp/ollin_gfx_graphics_b.png"
const SHOT_C = "/tmp/ollin_gfx_graphics_c.png"
const SHOT_D = "/tmp/ollin_gfx_graphics_d.png"
const SHOT_E = "/tmp/ollin_gfx_graphics_e.png"

global frames = 0
global updates = 0
global lastDt = -1

func update(dt)
    updates += 1
    lastDt = dt
end

func refusal(f)
    var msg = ""
    try
        f()
    catch e
        msg = e
    end
    return msg
end

func expect(got, want)
    assert(got == want, "want [{want}] got [{got}]")
end

func near(a, b)
    return math.abs(a - b) < 0.02
end

func is(img, x, y, r, g, b)
    var pr, pg, pb, pa = image.getPixel(img, x, y)
    return near(pr, r) and near(pg, g) and near(pb, b)
end

## How many pixels of the box are not black.
func lit(img, x0, y0, x1, y1)
    var n = 0
    for y = y0, y1 do
        for x = x0, x1 do
            var r, g, b, a = image.getPixel(img, x, y)
            if r + g + b > 0.05 then
                n += 1
            end
        end
    end
    return n
end

func setup()
    graphics.canvas(100, 80, "graphics test")
    graphics.antialias(false)
    dot = image.fromPattern(["##", "##"], {"#": Color(0, 1, 0)})   ## made OUTSIDE draw: creating a target there unbinds the frame's
end

## ── state that can be read back, and what is refused ──────────────────────
func check_state()
    assert(graphics.isOpen() == true)
    assert(graphics.fps() >= 0)
    graphics.stats(false)
    graphics.stats()
    graphics.fitArea(false)
    graphics.fitArea()
    graphics.fitArea(false)

    assert(graphics.fontSize() == 18)
    assert(graphics.fontSize(24) == 24)
    assert(graphics.fontSize() == 24)
    graphics.fontSize(18)
    assert(graphics.font() == "sans")
    assert(graphics.font("mono") == "mono")
    assert(graphics.font("pixel") == "pixel")
    assert(graphics.font(nil) == "pixel")
    graphics.font("sans")
    var w, h = graphics.textSize("Hello")
    assert(w > 20 and h > 10)
    var w2, h2 = graphics.textSize(42)
    var w3, h3 = graphics.textSize("42")
    assert(w2 == w3 and h2 == h3)
    graphics.fontSize(36)
    var wBig, hBig = graphics.textSize("Hello")
    assert(wBig > w * 1.5 and hBig > h * 1.5)
    graphics.fontSize(18)

    expect(refusal(func() graphics.font(5) end), "graphics.font: expected a font name")
    expect(refusal(func() graphics.font("no_such_font") end), "graphics.font: unknown font 'no_such_font' (available: sans, mono, pixel)")
    expect(refusal(func() graphics.textSize() end), "graphics.textSize: expected a text")
    expect(refusal(func() graphics.canvas(0, 10) end), "graphics.canvas: the width and the height must be positive")
    expect(refusal(func() graphics.canvas(10, 10, 5) end), "graphics.canvas: the title must be a string")
    expect(refusal(func() graphics.antialias(true, -1) end), "graphics.antialias: size must not be negative")
    graphics.antialias(false)
    expect(refusal(func() graphics.blendMode("no_such_mode") end), "graphics.blendMode: unknown mode 'no_such_mode'")
    expect(refusal(func() graphics.blendMode(true) end), "graphics.blendMode: expected a mode name or a blend constant")
    expect(refusal(func() graphics.viewport(10) end), "graphics.viewport: expected a width and a height")
    expect(refusal(func() graphics.viewport(0, 10) end), "graphics.viewport: the width and the height must be positive")
    expect(refusal(func() graphics.line(1, 2) end), "graphics.line: expected x1, y1, x2, y2")
    expect(refusal(func() graphics.rect(1, 2, 3) end), "graphics.rect: expected x, y, w, h[, r]")
    expect(refusal(func() graphics.text("a", 1) end), "graphics.text: expected text, x, y")
    expect(refusal(func() graphics.screenshot() end), "graphics.screenshot: expected a file path")
    expect(refusal(func() graphics.ellipse(1, 2, 3) end), "graphics.ellipse: expected x, y, width, height")
    expect(refusal(func() graphics.circle(1, 2) end), "graphics.circle: expected x, y, radius")
    expect(refusal(func() graphics.arc(1, 2, 3, 4, 5) end), "graphics.arc: expected x, y, w, h, start, stop")
    expect(refusal(func() graphics.point(1) end), "graphics.point: expected x, y")
    expect(refusal(func() graphics.polygon(5) end), "graphics.polygon: expected array of points")
    expect(refusal(func() graphics.polyline(5) end), "graphics.polyline: expected array of points")
    expect(refusal(func() graphics.translate(1) end), "graphics.translate: expected x, y [, z]")
    expect(refusal(func() graphics.rotate(10, 1) end), "graphics.rotate: expected deg [, ax, ay, az] (a whole axis, or none)")
    expect(refusal(func() graphics.scale() end), "graphics.scale: expected s | sx, sy | sx, sy, sz")
    expect(refusal(func() graphics.sprite(1) end), "graphics.sprite: expected img, x, y")
    expect(refusal(func() graphics.sprite(5, 1, 2) end), "graphics.sprite: expected image handle")
    assert(refusal(func() graphics.rectMode("no_such") end) <> "")
    assert(refusal(func() graphics.ellipseMode("no_such") end) <> "")
    assert(refusal(func() graphics.spriteMode("no_such") end) <> "")
    assert(refusal(func() graphics.textMode("no_such") end) <> "")
    assert(refusal(func() graphics.textMode("left", "no_such") end) <> "")
    assert(refusal(func() graphics.fill("red") end) <> "")
    expect(refusal(func() graphics.run() end), "graphics.run: expected callback function")
end

## ── scene A: shapes ────────────────────────────────────────────────────────
func scene_a()
    graphics.clear(0, 0, 0)
    graphics.noStroke()
    graphics.fill(1, 0, 0)
    graphics.rect(5, 5, 20, 10)                        ## a plain rectangle
    graphics.rectMode("center")
    graphics.fill(0, 1, 0)
    graphics.rect(45, 10, 10, 10)                      ## anchored by its centre
    graphics.rectMode("corner")
    graphics.fill(0, 0, 1)
    graphics.rect(60, 5, 24, 24, 8)                    ## rounded corners
    graphics.rect(90, 5, 8, 8, 100)                    ## a radius beyond the half side: a capsule
    graphics.fill(1, 1, 0)
    graphics.circle(15, 45, 8)
    graphics.ellipseMode("corner")
    graphics.ellipse(30, 37, 16, 16)                   ## its box starts at x, y
    graphics.ellipseMode("center")
    graphics.fill(0, 1, 1)
    graphics.polygon([[55, 35], [75, 35], [65, 55]])   ## a triangle
    graphics.fill(1, 0, 1)
    graphics.arc(88, 45, 16, 16, 0, 270)               ## a pie slice
    graphics.stroke(1, 1, 1)
    graphics.strokeSize(2)
    graphics.noFill()
    graphics.rect(5, 60, 20, 16)                       ## an outline: the inside stays black
    graphics.rect(30, 60, 20, 16, 5)                   ## a rounded outline
    graphics.rect(55, 60, 6, 6, 2)                     ## a stroke thicker than half the shorter side
    graphics.strokeSize(8)
    graphics.rect(66, 60, 6, 6)
    graphics.rect(76, 60, 8, 8, 2)
    graphics.strokeSize(2)
    graphics.line(90, 60, 98, 60)
    graphics.polyline([[88, 66], [98, 66], [98, 76]])
    graphics.point(90, 72)
    graphics.segments(12)
    graphics.circle(50, 70, 3)
    graphics.segments(64)
    graphics.screenshot(SHOT_A)
end

func check_a()
    var s = image.load(SHOT_A)
    assert(is(s, 10, 8, 1, 0, 0) and is(s, 4, 8, 0, 0, 0) and is(s, 26, 8, 0, 0, 0))
    assert(is(s, 45, 10, 0, 1, 0) and is(s, 40, 10, 0, 1, 0) and is(s, 39, 10, 0, 0, 0))
    assert(is(s, 72, 17, 0, 0, 1) and is(s, 60, 5, 0, 0, 0))
    assert(is(s, 94, 9, 0, 0, 1))
    assert(is(s, 15, 45, 1, 1, 0) and is(s, 15, 36, 0, 0, 0))
    assert(is(s, 38, 45, 1, 1, 0) and is(s, 30, 37, 0, 0, 0))
    assert(is(s, 65, 40, 0, 1, 1) and is(s, 55, 55, 0, 0, 0))
    assert(is(s, 88, 40, 1, 0, 1))
    assert(is(s, 5, 68, 1, 1, 1) and is(s, 15, 68, 0, 0, 0))
    assert(lit(s, 30, 60, 49, 75) > 40 and is(s, 40, 68, 0, 0, 0))
    assert(lit(s, 55, 60, 61, 66) > 20)
    assert(lit(s, 66, 60, 72, 66) > 20)
    assert(lit(s, 76, 60, 84, 68) > 20)
    assert(lit(s, 90, 59, 98, 61) > 8)
    assert(lit(s, 88, 66, 98, 76) > 15)
    assert(lit(s, 49, 66, 53, 74) > 5)
    image.unload(s)
end

## ── scene B: transforms, text, blending, tint, sprites ────────────────────
global dot = nil

func scene_b()
    graphics.clear(0, 0, 0)
    graphics.noStroke()
    graphics.fill(1, 0, 0)
    graphics.push()
    graphics.translate(10, 10)
    graphics.rect(0, 0, 10, 10)                        ## moved
    graphics.pop()
    graphics.rect(0, 0, 4, 4)                          ## the origin again
    graphics.pushMatrix()
    graphics.translate(40, 10)
    graphics.scale(2)
    graphics.rect(0, 0, 5, 5)                          ## doubled: 10 x 10
    graphics.scale(1, 2)
    graphics.rect(0, 0, 3, 3)
    graphics.scale(1, 1, 1)
    graphics.popMatrix()
    graphics.pushMatrix()
    graphics.translate(70, 20)
    graphics.rotate(90)
    graphics.fill(0, 1, 0)
    graphics.rect(0, 0, 10, 4)                         ## turned a quarter: it hangs down
    graphics.rotate(-90)
    graphics.rotateZ(90)
    graphics.rotateX(0)
    graphics.rotateY(0)
    graphics.rotate(0, 0, 0, 1)
    graphics.popMatrix()
    graphics.translate(0, 0)
    graphics.resetTransform()
    graphics.rect(0, 30, 2, 2)

    graphics.pushStyle()
    graphics.fill(0, 0, 1)
    graphics.strokeSize(5)
    graphics.fontSize(30)
    graphics.font("mono")
    graphics.rectMode("center")
    graphics.popStyle()
    assert(graphics.fontSize() == 18 and graphics.font() == "sans")
    graphics.rect(10, 30, 4, 4)                        ## the style is back: green, as when pushStyle ran

    graphics.fill(1, 1, 1)
    graphics.stroke(1, 1, 1)
    graphics.fontSize(14)
    graphics.textMode("left", "top")
    graphics.text("Ab", 4, 36)
    graphics.textMode("center", "center")
    graphics.text("Ab", 50, 44)
    graphics.textMode("right", "bottom")
    graphics.text("Ab", 96, 56)
    graphics.textMode("corner", "baseline")
    graphics.text(7, 4, 76)
    graphics.textMode("left", "top")
    graphics.fontSize(18)
    graphics.noStroke()

    graphics.fill(0.5, 0, 0)
    graphics.rect(60, 36, 10, 10)
    graphics.blendMode("add")
    graphics.rect(60, 36, 10, 10)                      ## 0.5 + 0.5 red
    graphics.blendMode("alpha")
    graphics.fill(0, 0, 1, 0.5)
    graphics.rect(74, 36, 10, 10)                      ## half a blue over black
    graphics.blendMode("multiply")
    graphics.blendMode("subtract")
    graphics.blendMode("add_colors")
    graphics.blendMode("premultiply")
    graphics.blendMode(blend.ALPHA)
    graphics.blendMode()

    graphics.tint(0.5, 0.5, 0.5)
    graphics.sprite(dot, 4, 66, 6, 6)                  ## tinted to half
    graphics.noTint()
    graphics.sprite(dot, 14, 66, 6, 6)
    graphics.spriteMode("center")
    graphics.sprite(dot, 30, 69, 6, 6)
    graphics.spriteMode("corner")
    graphics.sprite(dot, 38, 66)
    graphics.sprite(dot, 42, 66, 0, 0)
    graphics.clear(0, 0, 0, 0.5)                       ## a fade: halves what is there
    graphics.screenshot(SHOT_B)
end

func check_b()
    var s = image.load(SHOT_B)
    ## the fade at the end of the frame halved everything: a red is 0.5, a green 0.5, a half blue 0.25
    assert(is(s, 15, 15, 0.5, 0, 0) and is(s, 2, 2, 0.5, 0, 0))
    assert(is(s, 45, 15, 0.5, 0, 0))
    assert(lit(s, 38, 8, 52, 30) > 100)
    assert(lit(s, 66, 20, 70, 30) > 30 and lit(s, 71, 20, 80, 30) == 0)
    assert(is(s, 1, 31, 0, 0.5, 0) and is(s, 10, 30, 0, 0.5, 0))
    assert(lit(s, 4, 36, 30, 52) > 15)
    assert(lit(s, 40, 36, 62, 52) > 15)
    assert(lit(s, 70, 40, 96, 58) > 15)
    assert(lit(s, 4, 56, 30, 78) > 5)
    assert(is(s, 65, 41, 0.5, 0, 0))
    assert(is(s, 79, 41, 0, 0, 0.25))
    assert(is(s, 7, 69, 0, 0.25, 0) and is(s, 17, 69, 0, 0.5, 0))
    assert(lit(s, 27, 66, 34, 72) > 20)
    image.unload(s)
end

## ── scene C: outlines, thin strokes, the forms of the style calls ─────────
func scene_c()
    graphics.clear()
    graphics.noFill()
    graphics.stroke(1, 1, 1)
    graphics.strokeSize(4)
    graphics.ellipse(25, 20, 30, 16)                   ## an oval outline
    graphics.arc(70, 20, 30, 30, 0, 180)               ## an arc outline
    graphics.arc(70, 20, 30, 30, 270, 90)              ## through the zero: the stop wraps round
    graphics.arc(70, 20, 30, 30, 10, 10)               ## a degenerate arc
    graphics.strokeSize(0.5)
    graphics.line(5, 40, 40, 40)                       ## thinner than a pixel: a 1 px line, paler
    graphics.strokeSize(2)
    graphics.polyline([50, 40, 70, 40, 70, 50])        ## flat coordinates, two by two
    graphics.polyline([])                              ## nothing to draw
    graphics.polygon([[5, 50], [20, 50], [12, 62]])    ## a polygon outline
    graphics.polygon([[5, 70]])                        ## fewer than three points
    graphics.stroke(Color(0, 1, 0), 6)                 ## a Color and a size together
    graphics.line(30, 55, 45, 55)
    graphics.stroke()                                  ## no argument: stroke back on, same colour
    graphics.noStroke()
    graphics.stroke()
    graphics.line(50, 60, 60, 60)
    graphics.fill()
    graphics.noFill()
    graphics.tint()
    graphics.fill(Color(1, 0, 0))
    graphics.noStroke()
    graphics.rect(80, 60, 10, 10)
    graphics.screenshot(SHOT_C)
end

func check_c()
    var s = image.load(SHOT_C)
    assert(lit(s, 10, 12, 40, 28) > 100)
    assert(is(s, 25, 20, 0, 0, 0))
    assert(lit(s, 55, 20, 85, 36) > 40)
    assert(lit(s, 5, 39, 40, 41) > 20)
    var pr, pg, pb, pa = image.getPixel(s, 20, 40)
    assert(pr > 0.2 and pr < 0.8)
    assert(lit(s, 50, 38, 71, 52) > 40)
    assert(lit(s, 5, 50, 20, 62) > 20 and is(s, 12, 54, 0, 0, 0))
    assert(is(s, 38, 55, 0, 1, 0))
    assert(lit(s, 50, 59, 60, 61) > 8)
    assert(is(s, 85, 65, 1, 0, 0))
    image.unload(s)
end

## ── scene D: a viewport letterboxes what the script draws ────────────────
func scene_d()
    graphics.clear(0, 0, 0)
    graphics.noStroke()
    graphics.fill(1, 0, 0)
    graphics.rect(0, 0, 40, 40)                        ## the whole viewport
    graphics.screenshot(SHOT_D)
end

func check_d()
    var s = image.load(SHOT_D)
    assert(is(s, 50, 40, 1, 0, 0) and is(s, 12, 4, 1, 0, 0) and is(s, 88, 76, 1, 0, 0))
    assert(is(s, 5, 40, 0, 0, 0) and is(s, 95, 40, 0, 0, 0))
    image.unload(s)
end

## ── scene E: the engine fonts are distance fields, drawn sharp at a large size ──
func scene_e()
    graphics.clear(0, 0, 0)
    graphics.stroke(1, 1, 1)
    graphics.fontSize(70)
    graphics.textMode("left", "baseline")
    graphics.text("H", 5, 70)                          ## the capital H has neither descender nor overshoot
    graphics.screenshot(SHOT_E)
end

func check_e()
    var s = image.load(SHOT_E)
    assert(lit(s, 5, 66, 40, 69) > 10)                 ## the stems reach the baseline...
    assert(lit(s, 0, 72, 99, 79) == 0)                 ## ...and nothing hangs below it, margin of the glyph's rectangle included
    assert(lit(s, 0, 0, 99, 23) == 0 and lit(s, 5, 26, 40, 28) > 10)    ## the capital is about 44 px high
    var solid = 0                                      ## the stem is fully white inside: an edge, not a blur
    for x = 5, 50 do
        var r, g, b, a = image.getPixel(s, x, 45)
        if r > 0.97 then
            solid += 1
        end
    end
    assert(solid >= 8)
    image.unload(s)
end

## ── the viewport variables ────────────────────────────────────────────────
func check_viewport()
    graphics.viewport(50, 40)
    assert(W == 50 and H == 40 and CX == 25 and CY == 20 and SIZE == 40)
    graphics.viewport()
    assert(W == 100 and H == 80)
end

func draw()
    frames += 1
    if frames == 1 then
        check_state()
        check_viewport()
        scene_a()
    elseif frames == 2 then
        check_a()
        scene_b()
    elseif frames == 3 then
        check_b()
        scene_c()
    elseif frames == 4 then
        check_c()
        graphics.viewport(40, 40)                      ## takes effect with the next frame
    elseif frames == 5 then
        scene_d()
    elseif frames == 6 then
        check_d()
        graphics.viewport()                            ## takes effect with the next frame
    elseif frames == 7 then
        scene_e()
    elseif frames == 8 then
        check_e()
        assert(updates >= 5 and lastDt >= 0)
        var gone = image.fromPattern(["#"])
        image.unload(gone)
        expect(refusal(func() graphics.sprite(gone, 1, 2) end), "")        ## an unloaded image draws nothing
        expect(refusal(func() graphics.sprite({}, 1, 2) end), "graphics.sprite: invalid image handle")
        graphics.quit()
    end
end
