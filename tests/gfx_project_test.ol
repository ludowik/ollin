## graphics.project asked before the drawing area exists: there is no screen to land on, so no pixel — not a NaN
## that would pass every comparison silently. It needs a window, so it runs under Xvfb with the raylib build
## (tests/run_gfx.sh).

global cam = nil

func setup()
    cam = graphics.camera(0, 0, 5, 0, 0, 0)
    var x, y, depth = graphics.project(cam, 0, 0, 0)
    assert(x == nil and y == nil and depth > 4.99 and depth < 5.01, "before the canvas: {x} {y} {depth}")
    graphics.canvas(120, 90, "project test")
end

func draw()
    var x, y, depth = graphics.project(cam, 0, 0, 0)
    assert(x > 59 and x < 61 and y > 44 and y < 46, "with the canvas: {x} {y}")
    graphics.quit()
end
