## The image module for real: textures, render targets, pixel access, loading. It needs a window and a GL
## context, so it runs under Xvfb with the raylib build (tests/run_gfx.sh) — the headless build has no
## `image` (nil).

const PNG_2X2 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAE0lEQVR4nGP4z8DwHwyBNAgwAABIyQj4ccUx4AAAAABJRU5ErkJggg=="
const SHOT = "/tmp/ollin_gfx_image_test.png"

global frames = 0

## Runs f() and returns the message it fails with, "" when it does not fail.
func refusal(f)
    var msg = ""
    try
        f()
    catch e
        msg = e
    end
    return msg
end

func near(a, b)
    return math.abs(a - b) < 0.01
end

func pixel_is(img, x, y, r, g, b, a)
    var pr, pg, pb, pa = image.getPixel(img, x, y)
    return near(pr, r) and near(pg, g) and near(pb, b) and near(pa, a)
end

func setup()
    graphics.canvas(64, 48, "image test")
    graphics.antialias(false)   ## the pixels read back from the screenshot must be the drawn ones, not blurred edges
end

## ── loading ────────────────────────────────────────────────────────────────
func check_loading()
    var img = image.loadData("png", PNG_2X2)
    assert(img.width == 2 and img.height == 2)
    assert(pixel_is(img, 0, 0, 1, 0, 0, 1))
    assert(pixel_is(img, 1, 0, 0, 1, 0, 1))
    assert(pixel_is(img, 0, 1, 0, 0, 1, 1))
    assert(pixel_is(img, 1, 1, 1, 1, 1, 0))
    var dotted = image.loadData(".png", PNG_2X2)
    assert(dotted.width == 2)
    assert(refusal(func() image.loadData("png", "") end) == "image.loadData: empty or invalid base64 data")
    assert(refusal(func() image.loadData("png", "AAAA") end) == "image: failed to decode image (ext: .png)")
    assert(refusal(func() image.loadData(5, "AAAA") end) == "image.loadData: expected format string and base64 string")
    assert(refusal(func() image.load(5) end) == "image.load: expected path string")
    assert(refusal(func() image.load("no_such_image.png") end) == "image.load: cannot open 'no_such_image.png'")
    image.unload(img)
    image.unload(dotted)
end

## ── render targets and pixel access ───────────────────────────────────────
func check_pixels()
    var rt = image.create(8, 6)
    assert(rt.width == 8 and rt.height == 6)
    assert(pixel_is(rt, 0, 0, 0, 0, 0, 0))

    ## setPixel by Color and by components; outside the image is ignored, and reads back transparent.
    image.setPixel(rt, 1, 1, Color(1, 0, 0))
    image.setPixel(rt, 2, 1, 0, 1, 0, 1)
    image.setPixel(rt, 3, 1, 0, 0, 1, 0.5)
    image.setPixel(rt, -1, 0, Color(1, 1, 1))
    image.setPixel(rt, 8, 0, Color(1, 1, 1))
    image.setPixel(rt, 0, 6, Color(1, 1, 1))
    assert(pixel_is(rt, 1, 1, 1, 0, 0, 1))
    assert(pixel_is(rt, 2, 1, 0, 1, 0, 1))
    assert(pixel_is(rt, 3, 1, 0, 0, 1, 0.5))
    assert(pixel_is(rt, -1, 0, 0, 0, 0, 0))
    assert(pixel_is(rt, 8, 0, 0, 0, 0, 0))
    assert(pixel_is(rt, 0, 6, 0, 0, 0, 0))
    assert(refusal(func() image.setPixel(rt, 0, 0, 5) end) == "image: expected Color object")
    image.endPixels(rt)
    image.endPixels(rt)
    assert(pixel_is(rt, 1, 1, 1, 0, 0, 1))

    ## beginPixels / endPixels bracket a batch; mapPixel visits every pixel with its channels, and a
    ## function that returns fewer values leaves the others alone.
    image.beginPixels(rt)
    image.beginPixels(rt)
    image.setPixel(rt, 0, 0, Color(0.5, 0.5, 0.5))
    image.endPixels(rt)
    var visited = 0
    image.mapPixel(rt, func(x, y, r, g, b, a)
        visited += 1
        if x == 0 and y == 0 then
            return 1 - r, 1 - g
        end
    end)
    assert(visited == 48)
    assert(pixel_is(rt, 0, 0, 0.5, 0.5, 0.5, 1))
    assert(pixel_is(rt, 1, 1, 1, 0, 0, 1))
    assert(refusal(func() image.mapPixel(rt, 5) end) == "image.mapPixel: second argument must be a function")
    assert(refusal(func() image.mapPixel(rt) end) == "image.mapPixel: expected img, fn")
    var thrown = refusal(func() image.mapPixel(rt, func(x, y, r, g, b, a) throw "stop" end) end)
    assert(thrown == "stop")
    image.setPixel(rt, 4, 4, Color(0, 1, 1))
    assert(pixel_is(rt, 4, 4, 0, 1, 1, 1))

    ## Drawing INTO the target, then reading it back: the rows come back top-down.
    image.beginDraw(rt)
    graphics.clear(0, 0, 1)
    graphics.fill(1, 1, 0)
    graphics.noStroke()
    graphics.rect(0, 0, 4, 3)
    image.endDraw()
    assert(pixel_is(rt, 1, 1, 1, 1, 0, 1))
    assert(pixel_is(rt, 6, 5, 0, 0, 1, 1))
    image.setPixel(rt, 7, 0, Color(1, 0, 0))
    assert(pixel_is(rt, 7, 0, 1, 0, 0, 1))
    assert(pixel_is(rt, 1, 1, 1, 1, 0, 1))
    image.unload(rt)
    image.unload(rt)
    image.unload(5)
    image.unload()
    assert(refusal(func() image.getPixel(rt, 0, 0) end) == "image.getPixel: expected image handle")

    ## The checks every function makes on its arguments.
    assert(refusal(func() image.getPixel({}, 0, 0) end) == "image.getPixel: expected image handle")
    assert(refusal(func() image.getPixel() end) == "image.getPixel: expected img, x, y")
    assert(refusal(func() image.setPixel() end) == "image.setPixel: expected img, x, y, color")
    assert(refusal(func() image.draw() end) == "image.draw: expected img, x, y")
    assert(refusal(func() image.beginDraw() end) == "image.beginDraw: expected image handle")
    assert(refusal(func() image.beginPixels() end) == "image.beginPixels: expected image handle")
    assert(refusal(func() image.endPixels() end) == "image.endPixels: expected image handle")
    assert(refusal(func() image.create(4) end) <> "")
    var loaded = image.loadData("png", PNG_2X2)
    assert(refusal(func() image.beginDraw(loaded) end) == "image.beginDraw: not a render texture — use image.create()")
    ## Writing into a loaded image: its pixels are read back from the GPU first, then the write is kept.
    image.setPixel(loaded, 0, 0, Color(0, 0, 0))
    image.endPixels(loaded)
    assert(pixel_is(loaded, 0, 0, 0, 0, 0, 1))
    assert(pixel_is(loaded, 1, 0, 0, 1, 0, 1))
    image.unload(loaded)
end

## ── sprites from a pattern ────────────────────────────────────────────────
func check_patterns()
    var plain = image.fromPattern(["#.", ".#"])
    assert(plain.width == 2 and plain.height == 2)
    assert(pixel_is(plain, 0, 0, 1, 1, 1, 1))
    assert(pixel_is(plain, 1, 0, 0, 0, 0, 0))
    assert(pixel_is(plain, 1, 1, 1, 1, 1, 1))
    var painted = image.fromPattern(["o #", "#o "], {"#": Color(0, 0, 1), "o": Color(1, 0.4, 0.4)})
    assert(painted.width == 3 and painted.height == 2)
    assert(pixel_is(painted, 0, 0, 1, 0.4, 0.4, 1))
    assert(pixel_is(painted, 1, 0, 0, 0, 0, 0))
    assert(pixel_is(painted, 2, 0, 0, 0, 1, 1))
    assert(pixel_is(painted, 0, 1, 0, 0, 1, 1))
    var viaNil = image.fromPattern(["#"], nil)
    assert(pixel_is(viaNil, 0, 0, 1, 1, 1, 1))
    assert(refusal(func() image.fromPattern() end) == "image.fromPattern: expected an array of strings, one per row")
    assert(refusal(func() image.fromPattern([]) end) == "image.fromPattern: the pattern has no row")
    assert(refusal(func() image.fromPattern(["#", 5]) end) == "image.fromPattern: row 2 is not a string")
    assert(refusal(func() image.fromPattern(["##", "#"]) end) == "image.fromPattern: row 2 is 1 characters wide, row 1 is 2")
    assert(refusal(func() image.fromPattern([""]) end) == "image.fromPattern: the rows are empty")
    assert(refusal(func() image.fromPattern(["#"], 5) end) == "image.fromPattern: the palette must be a map of character to Color")
    assert(refusal(func() image.fromPattern(["#x"], {"#": Color(1, 1, 1)}) end) == "image.fromPattern: 'x' at row 1, column 2 is not in the palette")
    image.unload(plain)
    image.unload(painted)
    image.unload(viaNil)
end

## ── drawing images on the screen ──────────────────────────────────────────
global stamp = nil
global target = nil

func prepare_images()
    stamp = image.fromPattern(["##", "##"], {"#": Color(1, 0, 0)})
    target = image.create(4, 4)
    image.beginDraw(target)
    graphics.clear(0, 1, 0)
    image.endDraw()
end

func draw_images()
    graphics.clear(0, 0, 0)
    image.draw(stamp, 2, 2)                              ## its own size
    image.draw(stamp, 10, 2, 6, 6)                       ## stretched
    image.draw(stamp, 20, 2, 4, 4, Color(0, 0, 1))       ## an explicit tint
    graphics.tint(0.5, 0.5, 0.5)
    image.draw(stamp, 30, 2)                             ## the global tint
    graphics.noTint()
    graphics.spriteMode("center")
    image.draw(stamp, 44, 10, 8, 8)                      ## anchored by its centre
    graphics.spriteMode("corner")
    image.draw(target, 2, 20, 8, 8)                      ## a render target, rows flipped back
    graphics.sprite(stamp, 14, 20, 4, 4)
    graphics.screenshot(SHOT)
end

func draw()
    frames += 1
    if frames == 1 then
        check_loading()
        check_pixels()
        check_patterns()
        prepare_images()
    end
    draw_images()
    if frames == 3 then
        ## The screenshot written at the end of frame 2 is a PNG on disk: image.load reads it back.
        var shot = image.load(SHOT)
        assert(shot.width >= 64 and shot.height >= 48)
        assert(pixel_is(shot, 3, 3, 1, 0, 0, 1))
        assert(pixel_is(shot, 12, 4, 1, 0, 0, 1))
        assert(pixel_is(shot, 22, 4, 0, 0, 0, 1))
        assert(pixel_is(shot, 31, 3, 0.5, 0, 0, 1))
        assert(pixel_is(shot, 44, 10, 1, 0, 0, 1))
        assert(pixel_is(shot, 5, 23, 0, 1, 0, 1))
        assert(pixel_is(shot, 15, 21, 1, 0, 0, 1))
        assert(pixel_is(shot, 60, 44, 0, 0, 0, 1))
        image.unload(shot)
        graphics.quit()
    end
end
