var W = window.width
var H = window.height
const N = 20

var rects = []
for i = 1, N do
    var w = math.rand_int(30, 110)
    var h = math.rand_int(20, 80)
    rects[i] = {
        x: math.rand_int(0, W - w), y: math.rand_int(0, H - h),
        w: w, h: h,
        vx: math.rand(-2, 2), vy: math.rand(-2, 2),
        fc: Color.random(), sc: Color.random()
    }
end

graphics.canvas(W, H, "Rectangles")

func frame()
    graphics.clear(colors.BLACK)
    for r in rects do
        r.x += r.vx  r.y += r.vy
        if r.x < 0 or r.x + r.w > W then r.vx = -r.vx end
        if r.y < 0 or r.y + r.h > H then r.vy = -r.vy end
        r.x = math.clamp(r.x, 0, W - r.w)
        r.y = math.clamp(r.y, 0, H - r.h)
        graphics.fill(r.fc)
        graphics.stroke(r.sc)
        graphics.rect(r.x, r.y, r.w, r.h)
    end
    graphics.draw_text("FPS: "+graphics.fps(), W-80, H-20, 16)
end

graphics.run(frame)
