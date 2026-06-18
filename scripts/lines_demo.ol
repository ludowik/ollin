## animation : 40 lignes colorées qui bougent et rebondissent
const W = 800
const H = 600
const N = 40
const SPEED = 3

func rand_color()
    var r = math.floor(math.rand() * 200) + 55
    var g = math.floor(math.rand() * 200) + 55
    var b = math.floor(math.rand() * 200) + 55
    return (r << 24) | (g << 16) | (b << 8) | 255
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

for i = 1, N
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

while graphics.is_open()
    graphics.begin_draw()
    graphics.clear(graphics.BLACK)

    for i = 1, N
        x1[i]  = x1[i]  + vx1[i]
        y1[i]  = y1[i]  + vy1[i]
        x2[i]  = x2[i]  + vx2[i]
        y2[i]  = y2[i]  + vy2[i]

        if x1[i] < 0 or x1[i] > W then vx1[i] = -vx1[i] end
        if y1[i] < 0 or y1[i] > H then vy1[i] = -vy1[i] end
        if x2[i] < 0 or x2[i] > W then vx2[i] = -vx2[i] end
        if y2[i] < 0 or y2[i] > H then vy2[i] = -vy2[i] end

        graphics.line(x1[i], y1[i], x2[i], y2[i], cols[i])
    end

    graphics.draw_text("FPS: " + graphics.fps(), W - 80, H - 20, 16, graphics.WHITE)
    graphics.end_draw()
end

graphics.close()
