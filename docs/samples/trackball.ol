## A REUSABLE "trackball" rotation: dragging with the mouse or a finger turns a scene or an
## object, with no gimbal lock, by composing quaternions.
##
##   orient()  gives the current orientation quaternion, to pass to graphics.rotateq
##   dragging  → true while dragging, so an automatic rotation can be suspended
##   idle(degreesPerSecond)  a gentle rotation at rest, to be called in draw()
##   reset()   back to the starting orientation, for a "recentre the view" gesture
##
## Wiring on the host program's side. The mouse.* callbacks are GLOBAL to the engine, and a
## module cannot catch them itself, hence three relays:
##
##   import "trackball.ol"
##   global ball = Trackball()
##   func mouse.pressed(x, y)  ball.press(x, y) end
##   func mouse.moved(x, y)    ball.move(x, y)  end
##   func mouse.released(x, y) ball.release()   end
##   ## in draw(): graphics.rotateq(ball.orient())

class Trackball
    func init(sensitivity)
        self.q = graphics.quat()
        self.dragging = false
        self.lastx = 0
        self.lasty = 0
        ## Degrees of rotation per pixel dragged. The default only applies in the ABSENCE
        ## of an argument: `or` would also override 0, which deliberately freezes the
        ## rotation (zero is false in Ollin).
        self.sensitivity = 0.5
        if sensitivity <> nil then
            self.sensitivity = sensitivity
        end
    end

    func orient()
        return self.q
    end

    ## Back to the orientation of the first frame. The drag is released as well: a reset triggered
    ## in the middle of one would otherwise keep turning from the old reference point.
    func reset()
        self.q = graphics.quat()
        self.dragging = false
    end

    func press(x, y)
        self.dragging = true
        self.lastx = x
        self.lasty = y
    end

    func release()
        self.dragging = false
    end

    func move(x, y)
        if not self.dragging then
            return
        end
        var dx = (x - self.lastx) * self.sensitivity
        var dy = (y - self.lasty) * self.sensitivity
        self.lastx = x
        self.lasty = y
        ## dx turns around Y, dy around X; composed on the LEFT, hence in the SCREEN's frame,
        ## so the drag follows the finger whatever the orientation.
        var spin = graphics.quatAxis(0, 1, 0, dx).mul(graphics.quatAxis(1, 0, 0, dy))
        self.q = spin.mul(self.q)
    end

    ## A gentle rotation while the user is not dragging; it does nothing during a drag.
    func idle(degreesPerSecond)
        if self.dragging then
            return
        end
        self.q = graphics.quatAxis(0, 1, 0, deltaTime * degreesPerSecond).mul(self.q)
    end
end
