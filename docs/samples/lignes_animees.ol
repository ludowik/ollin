var W = window.width
var H = window.height
const N = 150
const SPEED = 3

class Line
    func init()
        self.x1 = math.rand_int(0, W)
        self.y1 = math.rand_int(0, H)
        self.x2 = math.rand_int(0, W)
        self.y2 = math.rand_int(0, H)
        self.vx1 = math.rand(-SPEED, SPEED)
        self.vy1 = math.rand(-SPEED, SPEED)
        self.vx2 = math.rand(-SPEED, SPEED)
        self.vy2 = math.rand(-SPEED, SPEED)
        self.col = Color.random()
    end

    func update()
        self.x1 += self.vx1  self.y1 += self.vy1
        self.x2 += self.vx2  self.y2 += self.vy2
        if self.x1 < 0 or self.x1 > W then self.vx1 = -self.vx1 end
        if self.y1 < 0 or self.y1 > H then self.vy1 = -self.vy1 end
        if self.x2 < 0 or self.x2 > W then self.vx2 = -self.vx2 end
        if self.y2 < 0 or self.y2 > H then self.vy2 = -self.vy2 end
    end

    func draw()
        graphics.stroke(self.col)
        graphics.line(self.x1, self.y1, self.x2, self.y2)
    end
end

var lines = []
for i = 1, N do
    lines[i] = Line()
end

graphics.canvas(W, H, "Lignes animées")

func frame()
    graphics.clear(colors.BLACK)
    graphics.strokeSize(1)
    for l in lines do
        l.update()
        l.draw()
    end
    graphics.draw_text("FPS: " + graphics.fps(), W-80, H-20, 16)
end

graphics.run(frame)
