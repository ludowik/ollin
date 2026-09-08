## A REUSABLE analogue touch joystick: a CIRCULAR area, neutral at the centre.
##
## A finger placed INSIDE the disc arms the control and keeps it active even if it leaves, the
## values being clamped. The neutral point is the disc's CENTRE:
##   steer()    in [-1;1], the horizontal offset from the centre (below 0 left, above 0 right)
##   throttle() in [-1;1], the vertical offset from the centre (above 0 forward, below 0 back)
##
## Wiring on the host program's side. A CLASS cannot receive a callback — nothing subscribes an
## object to the engine — so an instance needs three relays plus a draw:
##
##   import "../lib/joystick.ol"
##   global pad = Joystick()
##   func mouse.pressed(x, y)  pad.press(x, y)  end
##   func mouse.moved(x, y)    pad.move(x, y)   end
##   func mouse.released(x, y) pad.release()    end
##   ## in draw(): yaw -= pad.steer() * TURN_SPEED * deltaTime
##   ##              move by  pad.throttle() * SPEED * deltaTime  (negative goes backwards)
##   ## and at the end: pad.draw()
##
## The disc is placed and sized by three fractions of the drawing area — centerXFrac, centerFrac
## and radiusFrac — so a program whose whole field is played in can move the control out of the
## action instead of laying it over the middle of it.
##
## Set `floating` to arm the control WHEREVER the finger lands, the disc anchoring itself at that
## point for as long as the finger is down. The fractions then only say where the resting disc is
## drawn. That is what a thumb actually does on glass: it presses roughly where the control is and
## expects the neutral point to be under it, rather than having to hit a target while the game
## moves. Left off, the finger must land INSIDE the disc, which is right for a control the player
## can look at.

class Joystick
    func init()
        self.active = false       ## armed, a finger being down inside the disc; it stays true if the finger leaves
        self.px = 0
        self.py = 0
        self.floating = false     ## arm anywhere, the disc following the finger (see the header)
        self.ax = nil             ## the anchored neutral point, while a floating control is held
        self.ay = nil
        self.centerXFrac = 0.5   ## the neutral point's abscissa, as a fraction of W
        self.centerFrac = 0.72   ## the neutral point's height, as a fraction of H
        self.radiusFrac = 0.22   ## the disc's radius, as a fraction of H
        self.dead = 0.10          ## the dead zone around the centre, as a fraction of the radius
    end

    ## The neutral point: the anchor while a floating control is held, the resting place otherwise.
    func cx()
        if self.ax <> nil then
            return self.ax
        end
        return W * self.centerXFrac
    end
    func cy()
        if self.ay <> nil then
            return self.ay
        end
        return H * self.centerFrac
    end
    func radius()
        return H * self.radiusFrac
    end

    func press(x, y)
        self.px = x
        self.py = y
        if self.floating then
            self.ax = x
            self.ay = y
            self.active = true
            return
        end
        var dx = x - self.cx()
        var dy = y - self.cy()
        self.active = (dx * dx + dy * dy) <= self.radius() * self.radius()
    end
    func move(x, y)
        self.px = x
        self.py = y
    end
    func release()
        self.active = false
        self.ax = nil
        self.ay = nil
    end

    ## A dead zone at the centre, then a rescale: 0 inside the dead zone, ±1 at the edge.
    func shape(v)
        if v > 0 - self.dead and v < self.dead then
            return 0.0
        end
        var sign = 1.0
        if v < 0 then
            sign = -1.0
        end
        return sign * math.clamp((math.abs(v) - self.dead) / (1.0 - self.dead), 0.0, 1.0)
    end

    ## Steering in [-1;1]: the finger's horizontal offset from the centre.
    func steer()
        if not self.active or W <= 0 then
            return 0.0
        end
        return self.shape((self.px - self.cx()) / self.radius())
    end

    ## Throttle in [-1;1]: the vertical offset from the centre, up being forward and down back.
    func throttle()
        if not self.active or H <= 0 then
            return 0.0
        end
        return self.shape((self.cy() - self.py) / self.radius())
    end

    func draw()
        var cx = self.cx()
        var cy = self.cy()
        var r = self.radius()
        graphics.noStroke()
        graphics.fill(Color(1, 1, 1, 0.06))
        graphics.circle(cx, cy, r)
        graphics.fill(Color(1, 1, 1, 0.16))
        graphics.circle(cx, cy, r * self.dead + 4)    ## the neutral point
        if self.active then
            ## the thumb is held at the disc's edge, as a real stick would be
            var dx = self.px - cx
            var dy = self.py - cy
            var d = math.sqrt(dx * dx + dy * dy)
            var kx = self.px
            var ky = self.py
            if d > r then
                kx = cx + dx / d * r
                ky = cy + dy / d * r
            end
            graphics.stroke(Color(1, 1, 1, 0.45))
            graphics.line(cx, cy, kx, ky)
            graphics.noStroke()
            graphics.fill(Color(0.45, 0.65, 1.0, 0.85))
            graphics.circle(kx, ky, 20)
        end
    end
end
