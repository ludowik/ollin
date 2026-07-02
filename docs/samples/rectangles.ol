## Cycle de vie complet :
##   setup()      → appelée une fois après le chargement (init)
##   update(dt)   → logique, appelée chaque frame avant draw (dt = secondes)
##   draw()       → rendu, appelée chaque frame

## W et H (dimensions de la zone de rendu) sont fournis par le moteur.
global rects = []
const N = 20

class Rect
    func init()
        self.w = math.rand_int(30, 110)
        self.h = math.rand_int(20, 80)
        self.x = math.rand_int(0, W - self.w)
        self.y = math.rand_int(0, H - self.h)
        self.vx = math.rand(-120, 120)   ## pixels / seconde
        self.vy = math.rand(-120, 120)
        self.fc = Color.random()
        self.sc = Color.random()
    end

    func update(dt)
        self.x += self.vx * dt
        self.y += self.vy * dt
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

## init unique avant la boucle
func setup()
    graphics.canvas(W, H, "Rectangles")
    for i = 1, N do
        rects[i] = Rect()
    end
end

## logique (mouvement indépendant du framerate)
func update(dt)
    for r in rects do
        r.update(dt)
    end
end

## rendu
func draw()
    graphics.clear(colors.BLACK)
    for r in rects do
        r.draw()
    end
end
