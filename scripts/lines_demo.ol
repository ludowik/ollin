## animation : 200 lignes colorées qui bougent et rebondissent
const W = 800
const H = 600
const N = 200
const SPEED = 3

func rand_color()
    return Color(math.rand() * 0.8 + 0.2, math.rand() * 0.8 + 0.2, math.rand() * 0.8 + 0.2)
end

func rpos(max)
    return math.floor(math.rand() * max)
end

func rvel()
    return math.rand() * SPEED * 2 - SPEED
end

var x1 = []  var y1 = []  var x2 = []  var y2 = []
var vx1 = [] var vy1 = [] var vx2 = [] var vy2 = []
var cols = []

for i = 1, N do
    x1[i]  = rpos(W)
    y1[i]  = rpos(H)
    x2[i]  = rpos(W)
    y2[i]  = rpos(H)
    vx1[i] = rvel()
    vy1[i] = rvel()
    vx2[i] = rvel()
    vy2[i] = rvel()
    cols[i] = rand_color()
end

graphics.canvas(W, H, "Ollin — Lignes animées")

func frame()
    graphics.clear(graphics.BLACK)

    for i = 1, N do
        x1[i]  = x1[i]  + vx1[i]
        y1[i]  = y1[i]  + vy1[i]
        x2[i]  = x2[i]  + vx2[i]
        y2[i]  = y2[i]  + vy2[i]

        if x1[i] < 0 or x1[i] > W then vx1[i] = -vx1[i] end
        x1[i] = math.clamp(x1[i], 0, W)
        if y1[i] < 0 or y1[i] > H then vy1[i] = -vy1[i] end
        y1[i] = math.clamp(y1[i], 0, H)
        if x2[i] < 0 or x2[i] > W then vx2[i] = -vx2[i] end
        x2[i] = math.clamp(x2[i], 0, W)
        if y2[i] < 0 or y2[i] > H then vy2[i] = -vy2[i] end
        y2[i] = math.clamp(y2[i], 0, H)

        graphics.line(x1[i], y1[i], x2[i], y2[i], 1, cols[i])
    end

    graphics.draw_text("FPS: " + graphics.fps(), W - 80, H - 20, 16, graphics.WHITE)
end

graphics.run(frame)
