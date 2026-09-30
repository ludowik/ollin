## A minimal rally car: pedal and steering in, position and heading out. Deliberately generic — no
## terrain, no camera, no drawing, no keyboard reading — so any future third-person driving game can
## reuse it the way samples/lib/trackball.ol is reused for an orbit camera. rally.ol wires the three
## together. The speed comes from real forces (engine.ol's drive force against drag, rolling
## resistance and the brakes, limited by what the tyres can grip), so the top speed, the acceleration
## and the gear changes are consequences of the engine and not numbers set here.
import "engine.ol"

class Vehicle
    func init(x, z, heading)
        self.x = x
        self.z = z
        self.heading = heading or 0.0
        self.speed = 0.0       ## m/s along the heading; negative when reversing
        self.travelled = 0.0   ## signed distance rolled so far — what a wheel's spin is derived from
        self.engine = Engine()

        self.mass = 1000.0
        self.gripAccel = 8.0       ## m/s², the most the tyres can push the car forward (loose surface)
        self.brakeDecel = 9.0      ## m/s² at full brake
        self.dragArea = 1.0        ## Cd·A, m²; the drag force is ½·ρ·CdA·v²
        self.rolling = 0.02        ## rolling resistance coefficient
        self.turnRate = 1.6        ## rad/s at full steer, at walking pace
        self.cornerAccel = 16.0    ## m/s², the most lateral acceleration the tyres hold
        self.maxSteerAngle = 0.5   ## rad, how far the front wheels pivot at full steer
        self.steerAngle = 0.0      ## the front wheels' yaw, in the heading's own sign (positive = towards +heading)
    end

    ## throttle: -1 (brake, then reverse) .. 1 (accelerate). steer: -1 (left) .. 1 (right).
    func update(dt, throttle, steer)
        ## One pedal pair: the same input drives the engine in the direction of the pedal, or brakes
        ## when the car is moving the other way.
        var dir = 1
        var pedal = 0.0
        var brake = 0.0
        if throttle > 0 then
            if self.speed < -0.5 then
                brake = throttle
            else
                pedal = throttle
            end
        elseif throttle < 0 then
            if self.speed > 0.5 then
                brake = -throttle
            else
                pedal = -throttle
                dir = -1
            end
        elseif self.speed < 0 then
            dir = -1
        end

        var force = self.engine.update(dt, math.max(self.speed * dir, 0.0), pedal, dir < 0, brake)
        force = math.min(force, self.mass * self.gripAccel) * dir

        var sign = 0
        if self.speed > 0 then
            sign = 1
        elseif self.speed < 0 then
            sign = -1
        end
        var v = math.abs(self.speed)
        var resist = 0.5 * 1.2 * self.dragArea * v * v + self.rolling * self.mass * 9.81
                     + brake * self.brakeDecel * self.mass
        var nextSpeed = self.speed + (force - sign * resist) / self.mass * dt
        ## Resistance stops the car; it never pushes it the other way.
        if sign <> 0 and nextSpeed * sign < 0 then
            nextSpeed = 0.0
        end
        self.speed = nextSpeed

        ## A car cannot pivot standing still, and a real steering wheel turns the visible curve
        ## the OTHER way in reverse — both fall out of scaling by speed rather than by steer alone.
        ## The yaw rate is also capped by the lateral grip (v·ω ≤ cornerAccel): full lock at 50 m/s
        ## would otherwise ask for 80 m/s² and spin the car.
        var turnScale = math.clamp(self.speed / 4.0, -1, 1)
        var yawRate = math.min(self.turnRate, self.cornerAccel / math.max(math.abs(self.speed), 0.1))
        ## MINUS: with heading 0 facing +Z, +X is screen-LEFT as seen from behind the car (chase
        ## camera looking the same way) — checked by placing markers either side and reading which
        ## one the chase camera puts on the right. steer=-1 (left) must grow +X, so it subtracts.
        self.heading = self.heading - steer * yawRate * turnScale * dt

        ## Purely visual: the wheels ease towards the steering instead of snapping to it. The minus
        ## is the same one as on the heading — steer > 0 lowers the heading.
        self.steerAngle = self.steerAngle + (-steer * self.maxSteerAngle - self.steerAngle) * (1 - math.exp(-12 * dt))
        self.travelled = self.travelled + self.speed * dt
        self.x = self.x + math.sin(self.heading) * self.speed * dt
        self.z = self.z + math.cos(self.heading) * self.speed * dt
    end
end
