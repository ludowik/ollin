## A fixed field of STARS: seeded once over an area, then drawn with a global fade. Both eclipses
## drew their own, with the same three numbers per star and the same loop, differing only in how
## many, how high, and whether they fade with the daylight — so the field is described here once and
## the difference stays where it belongs, in the call.
##
## The stars are a FLAT array, [x, y, brightness, …]: three numbers per star and no map, an array of
## a few hundred entries being read every frame.
##
## Wiring on the host program's side:
##
##   import "../lib/starfield.ol"
##   global sky = Starfield(220, W, H, 0.15)   ## count, width, height, the faintest star
##   ## in setup(): sky.seed()
##   ## in draw():  sky.draw()  — or sky.draw(a) to fade the whole field, a in [0;1]
class Starfield
    func init(count, width, height, faintest)
        self.count = count
        self.width = width
        self.height = height
        self.faintest = faintest
        self.tint = Color(0.87, 0.92, 1)
        self.stars = []
    end

    ## The colour the stars are drawn in; the brightness of each one multiplies it.
    func color(c)
        self.tint = c
        return self
    end

    func seed()
        self.stars = []
        for i = 1, self.count do
            self.stars.push(math.rand(0, self.width))
            self.stars.push(math.rand(0, self.height))
            self.stars.push(math.rand(self.faintest, 1.0))
        end
        return self
    end

    ## `fade` scales the whole field, 1 by default: a sky that lightens simply passes a smaller
    ## number, and at zero nothing is drawn at all.
    func draw(fade = 1.0)
        if fade <= 0.0 then
            return
        end
        for i = 1, #self.stars, 3 do
            var e = self.stars[i + 2] * fade
            graphics.stroke(Color(self.tint.r, self.tint.g, self.tint.b, math.clamp(e, 0, 1)), e * 2)
            graphics.point(self.stars[i], self.stars[i + 1])
        end
    end
end
