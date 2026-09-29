## A minimal arcade car: throttle and steering in, position and heading out. Deliberately
## generic — no terrain, no camera, no drawing, no keyboard reading — so any future
## third-person driving game can reuse it the way samples/lib/trackball.ol is reused for an
## orbit camera. rally.ol wires the three together.
class Vehicle
    func init(x, z, heading)
        self.x = x
        self.z = z
        self.heading = heading or 0.0
        self.speed = 0.0

        self.accel = 18.0      ## units/s^2 while the throttle pushes with the current motion
        self.brake = 28.0      ## units/s^2 while it pushes against it (braking, not just easing off)
        self.friction = 6.0    ## units/s^2 of natural slowdown with no throttle at all
        self.maxSpeed = 32.0
        self.maxReverse = 12.0
        self.turnRate = 1.6    ## rad/s, at full steer, once turnScale below has ramped up
    end

    ## throttle: -1 (brake/reverse) .. 1 (accelerate). steer: -1 (left) .. 1 (right).
    func update(dt, throttle, steer)
        if throttle > 0 then
            var rate = self.accel
            if self.speed < 0 then rate = self.brake end
            self.speed = self.speed + rate * throttle * dt
        elseif throttle < 0 then
            var rate = self.accel
            if self.speed > 0 then rate = self.brake end
            self.speed = self.speed + rate * throttle * dt
        else
            var drop = self.friction * dt
            if self.speed > 0 then
                self.speed = math.max(0, self.speed - drop)
            elseif self.speed < 0 then
                self.speed = math.min(0, self.speed + drop)
            end
        end
        self.speed = math.clamp(self.speed, -self.maxReverse, self.maxSpeed)

        ## A car cannot pivot standing still, and a real steering wheel turns the visible curve
        ## the OTHER way in reverse — both fall out of scaling by speed rather than by steer alone.
        ## Ramped over a few units/s (not the full speed range) so steering is already at full
        ## strength well before top speed, rather than growing sluggish exactly when it matters
        ## least and staying weak exactly when leaving a corner matters most.
        var turnScale = math.clamp(self.speed / 4.0, -1, 1)
        ## MINUS: with heading 0 facing +Z, +X is screen-LEFT as seen from behind the car (chase
        ## camera looking the same way) — checked by placing markers either side and reading which
        ## one the chase camera puts on the right. steer=-1 (left) must grow +X, so it subtracts.
        self.heading = self.heading - steer * self.turnRate * turnScale * dt

        self.x = self.x + math.sin(self.heading) * self.speed * dt
        self.z = self.z + math.cos(self.heading) * self.speed * dt
    end
end
