## A steering wheel made of the phone's ROLL: tip the phone like a steering wheel, or like a tray,
## and the steering follows. It turns the angle motion.tilt() reports, in degrees, into a steering
## value in [-1;1] — the same range a joystick's steer() or the arrow keys give.
##
##   import "../lib/tilt.ol"
##   global wheel = Tilt(30, 3)
##   motion.enable()                     ## once, in setup() — iOS asks at the player's next tap
##   ## every frame, once motion.state() is "on":
##   var roll = motion.tilt()
##   steer = wheel.update(deltaTime, roll)
##
## The neutral position is wherever the phone was when `calibrate` last ran: nobody holds a phone
## the same way, and a fixed neutral would steer a little to one side for the whole drive.
## `fullLock` is the roll, in degrees from the neutral, that steers fully; `deadZone` the roll
## ignored around the neutral so a hand that is not perfectly still does not wander. Past the dead
## zone the steering rises from 0, not from a step, and the result is smoothed so that a sensor's
## jitter does not reach the wheels.
import "approach.ol"

class Tilt
    func init(fullLock, deadZone, rate)
        if fullLock == nil then
            fullLock = 30.0
        end
        if deadZone == nil then
            deadZone = 3.0
        end
        if rate == nil then
            rate = 12.0
        end
        assert(fullLock > deadZone, "Tilt: fullLock must be larger than deadZone")
        self.fullLock = fullLock
        self.deadZone = deadZone
        self.rate = rate          ## how eagerly the steering follows the roll (see approach.ol)
        self.neutral = 0.0
        self.steer = 0.0
    end

    func calibrate(roll)
        self.neutral = roll
    end

    func update(dt, roll)
        var offset = roll - self.neutral
        var past = math.max(math.abs(offset) - self.deadZone, 0.0)
        var target = math.clamp(past / (self.fullLock - self.deadZone), 0.0, 1.0)
        if offset < 0 then
            target = -target
        end
        self.steer = approach(self.steer, target, self.rate, dt)
        return self.steer
    end
end
