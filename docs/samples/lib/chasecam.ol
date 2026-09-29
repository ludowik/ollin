## A third-person follow camera: eases toward a position behind and above a target instead of
## snapping to it, so a sharp turn doesn't whip the view. Generic on purpose — it knows nothing
## about a car, a terrain or a control scheme, only a target position and a heading, the same
## spirit as trackball.ol for an orbit camera.
##
##   var chase = ChaseCamera(distance, height [, stiffness])
##   chase.update(dt, targetX, targetY, targetZ, headingRad)   ## every frame, before drawing
##   chase.apply(cam)                                          ## cam = graphics.camera(...)

class ChaseCamera
    func init(distance, height, stiffness)
        self.distance = distance
        self.height = height
        self.stiffness = 6.0
        if stiffness <> nil then
            self.stiffness = stiffness
        end
        self.x = 0.0
        self.y = height
        self.z = -distance
        self.targetX = 0.0
        self.targetY = 0.0
        self.targetZ = 0.0
        self.started = false
    end

    func update(dt, tx, ty, tz, heading)
        var wantX = tx - math.sin(heading) * self.distance
        var wantY = ty + self.height
        var wantZ = tz - math.cos(heading) * self.distance
        if self.started then
            var a = 1 - math.exp(-self.stiffness * dt)
            self.x = self.x + (wantX - self.x) * a
            self.y = self.y + (wantY - self.y) * a
            self.z = self.z + (wantZ - self.z) * a
        else
            self.x = wantX
            self.y = wantY
            self.z = wantZ
            self.started = true
        end
        self.targetX = tx
        self.targetY = ty
        self.targetZ = tz
    end

    func apply(cam)
        cam.setPos(self.x, self.y, self.z)
        cam.lookAt(self.targetX, self.targetY, self.targetZ)
    end
end
