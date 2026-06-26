var W = window.width
var H = window.height
const N = 20

class Rect
    func init()
        self.w = math.rand_int(30, 110)
        self.h = math.rand_int(20, 80)
        self.x = math.rand_int(0, W - self.w)
        self.y = math.rand_int(0, H - self.h)
        self.vx = math.rand(-2, 2)
        self.vy = math.rand(-2, 2)
        self.fc = Color.random()
        self.sc = Color.random()
    end

    func update()
        self.x += self.vx self.y += self.vy
        if self.x < 0 or self.x + self.w > W then self.vx = -self.vx end
        if self.y < 0 or self.y + self.h > H then self.vy = -self.vy end
        self.x = math.clamp(self.x, 0, W - self.w)
        self.y = math.clamp(self.y, 0, H - self.h)
    end

    func draw()
        graphics.fill(self.fc)
        graphics.stroke(self.sc)
        graphics.rect(self.x, self.y, self.w, self.h)
    end
end

var rects = []
for i = 1, N do
    rects[i] = Rect()
end

graphics.canvas(W, H, "Rectangles")

func frame()
    graphics.clear(colors.BLACK)
    for r in rects do
        r.update()
        r.draw()
    end
    graphics.draw_text("FPS: " + graphics.fps(), W-80, H-20, 16)
end

graphics.run(frame)
