## A rally car's powertrain, after a Super 5 class rally car: a high-revving petrol engine
## (9500 rpm limiter, power peaking near 8500), a five-speed gearbox with a short final drive, and an
## automatic shifter that tries to keep the engine near its power band. Deliberately generic like
## vehicle.ol: it knows nothing of terrain, camera or keyboard. Give it the car's speed along its
## direction of travel and the pedal every frame; it returns the force at the wheels and keeps the
## gear and the revs. EngineSound turns those revs into a note.
##
## Units are SI — metres, seconds, newtons, newton-metres — so the numbers below can be checked
## against a real car's: 9500 rpm in fifth is 50 m/s, 180 km/h, and first gear runs out at 53 km/h.
class Engine
    func init()
        self.idle = 1100.0
        self.limiter = 9500.0
        self.wheelRadius = 0.30
        self.efficiency = 0.88         ## the share of the engine's torque that reaches the ground
        self.finalDrive = 5.98
        self.ratios = [3.4, 2.15, 1.55, 1.22, 1.0]
        self.reverseRatio = 3.3
        ## The torque curve, in N·m: it fills out from idle to a broad peak near 6500, then falls
        ## away towards the limiter, so the engine pulls hardest in the middle of its range.
        self.rpmTable = [1100.0, 1500.0, 3000.0, 4500.0, 5500.0, 6500.0, 7500.0, 8500.0, 9500.0]
        self.nmTable = [60.0, 90.0, 130.0, 170.0, 195.0, 205.0, 200.0, 185.0, 160.0]
        self.reverseLimiter = 4500.0   ## reversing is cut far lower: about 26 km/h
        self.launchRpm = 5500.0        ## where the clutch lets the engine rev while pulling away in first
        self.shiftTime = 0.22          ## seconds with the drive cut while the gear changes
        self.gear = 1
        self.reverse = false
        self.rpm = self.idle
        self.shiftTimer = 0.0
        self.load = 0.0                ## the throttle, smoothed: what the sound swells with
    end

    ## Linear interpolation in the torque table; clamped to its ends.
    func torque(rpm)
        var r = self.rpmTable
        var t = self.nmTable
        if rpm <= r[1] then
            return t[1]
        end
        for i = 2, #r do
            if rpm <= r[i] then
                var k = (rpm - r[i - 1]) / (r[i] - r[i - 1])
                return t[i - 1] + (t[i] - t[i - 1]) * k
            end
        end
        return t[#t]
    end

    ## Engine revolutions per wheel revolution, the final drive included.
    func overall(g)
        if self.reverse then
            return self.reverseRatio * self.finalDrive
        end
        return self.ratios[g] * self.finalDrive
    end

    ## The speed at which the given gear reaches the limiter.
    func topSpeed(g)
        return self.limiter / 9.5493 * self.wheelRadius / self.overall(g)
    end

    ## One step. `speed` is the car's speed along its direction of travel (never negative),
    ## `throttle` the pedal in [0;1], `brake` the brake in [0;1]. Returns the drive force at the
    ## wheels in newtons along that direction — negative when the engine is braking the car.
    func update(dt, speed, throttle, reverse, brake)
        if reverse <> self.reverse then
            self.reverse = reverse
            self.gear = 1
        end
        self.load = self.load + (throttle - self.load) * (1 - math.exp(-8.0 * dt))

        if self.shiftTimer > 0 then
            self.shiftTimer = self.shiftTimer - dt
        elseif not self.reverse then
            ## Up near the power peak under load, earlier on a light pedal; down when the revs sag,
            ## and only if the lower gear would not over-rev. Braking raises the downshift point a
            ## lot: a driver slowing down drops gears early to keep the engine in its range and
            ## to use its braking, rather than staying in top until the revs are almost dead — and
            ## never shifts up while braking, or the revs a downshift raises would undo it.
            var up = 6500.0 + 2500.0 * throttle
            var down = 3500.0 + 1500.0 * throttle + 3500.0 * brake
            if self.gear < #self.ratios and self.rpm > up and brake <= 0 then
                self.gear = self.gear + 1
                self.shiftTimer = self.shiftTime
            elseif self.gear > 1 and self.rpm < down
                   and self.rpm * self.ratios[self.gear - 1] / self.ratios[self.gear] < self.limiter - 700.0 then
                self.gear = self.gear - 1
                self.shiftTimer = self.shiftTime
            end
        end

        var limit = self.limiter
        if self.reverse then
            limit = self.reverseLimiter
        end
        var total = self.overall(self.gear)
        var wheelRpm = speed / self.wheelRadius * total * 9.5493
        var target = wheelRpm
        if self.shiftTimer <= 0 and (self.gear == 1 or self.reverse) then
            ## The clutch slips when pulling away: the revs rise with the pedal before the car has
            ## any speed to give them.
            target = math.max(target, self.idle + (math.min(self.launchRpm, limit - 400.0) - self.idle) * throttle)
        end
        target = math.max(target, self.idle)
        var rate = 18.0
        if self.shiftTimer > 0 then
            rate = 7.0
        end
        self.rpm = self.rpm + (target - self.rpm) * (1 - math.exp(-rate * dt))

        if self.shiftTimer > 0 then
            return 0.0
        end
        ## A fuel cut at the limiter, over a few hundred rpm so it bounces rather than clicks.
        var cut = math.clamp((limit + 150.0 - self.rpm) / 150.0, 0.0, 1.0)
        var drag = (25.0 + 0.006 * self.rpm) * (1.0 - throttle)
        ## Engine braking fades out as the car stops, so a parked car does not creep backwards.
        drag = drag * math.min(speed, 1.0)
        var nm = self.torque(self.rpm) * throttle * cut - drag
        return nm * total / self.wheelRadius * self.efficiency
    end
end

## The engine's note: a soft triangle for the body and a quieter sawtooth for the buzz, both at the
## firing pitch. Pitch and level follow the revs and the throttle. The audio device only opens on
## the first user gesture, so the voices start silent and simply become audible once it does.
class EngineSound
    func init()
        self.pitchPerRev = 2.0     ## Hz per rpm/60: lower is deeper, higher is shriller
        self.body = nil
        self.buzz = nil
    end

    func start()
        self.body = sound.triangle(40).volume(0.0)
        self.buzz = sound.saw(40).volume(0.0)
        self.body.start()
        self.buzz.start()
    end

    func update(engine)
        if self.body == nil then
            return
        end
        var level = (engine.rpm - engine.idle) / (engine.limiter - engine.idle)
        var gain = 0.6 + 0.4 * level
        var pitch = engine.rpm / 60.0 * self.pitchPerRev
        self.body.freq(pitch).volume((0.08 + 0.10 * engine.load) * gain)
        self.buzz.freq(pitch).volume((0.02 + 0.06 * engine.load) * gain)
    end
end
