## An engine's revs from the car's speed and the throttle, and the sound they make. Deliberately
## generic like vehicle.ol: it knows nothing of terrain, camera or keyboard — feed it a speed and a
## throttle every frame, and it keeps a gear, a rev count and two oscillators in step.
class Engine
    func init(maxSpeed)
        self.idle = 900.0          ## rpm at rest
        self.redline = 6500.0
        ## The speed, as a fraction of maxSpeed, at which each gear reaches the redline — the top gear
        ## overshoots 1, so the car at full speed cruises a little under the redline.
        self.tops = [0.35, 0.68, 1.15]
        self.maxSpeed = maxSpeed
        self.gear = 1
        self.rpm = self.idle
        self.load = 0.0            ## 0 coasting .. 1 full throttle, smoothed — what the sound swells with
        self.main = nil
        self.sub = nil
    end

    ## The speed at which the given gear hits the redline.
    func gearTop(g)
        return self.tops[g] * self.maxSpeed
    end

    ## Creates the two voices. The device only opens on the first user gesture, so they are
    ## started silent here and simply become audible once it does.
    func start()
        self.main = sound.saw(60).volume(0.0)
        self.sub = sound.triangle(30).volume(0.0)
        self.main.start()
        self.sub.start()
    end

    func update(dt, speed, throttle)
        var s = math.abs(speed)

        ## Shift up at the redline, down well below the previous gear's top: the gap is what keeps
        ## the gearbox from hunting between two gears at a steady speed.
        if self.gear < #self.tops and s > self.gearTop(self.gear) * 0.97 then
            self.gear = self.gear + 1
        elseif self.gear > 1 and s < self.gearTop(self.gear - 1) * 0.8 then
            self.gear = self.gear - 1
        end

        var target = self.idle + (self.redline - self.idle) * math.min(s / self.gearTop(self.gear), 1.0)
        ## Pulling away in first gear, the clutch slips: the revs rise with the pedal before the car
        ## has any speed to give them.
        if self.gear == 1 then
            target = math.max(target, self.idle + (self.redline - self.idle) * 0.5 * math.abs(throttle))
        end

        ## The revs rise faster than they fall: an engine has inertia, and a lifted foot lets it
        ## die down rather than drop.
        var rate = 5.0
        if target > self.rpm then
            rate = 12.0
        end
        self.rpm = self.rpm + (target - self.rpm) * (1 - math.exp(-rate * dt))
        self.load = self.load + (math.abs(throttle) - self.load) * (1 - math.exp(-8.0 * dt))

        var level = (self.rpm - self.idle) / (self.redline - self.idle)
        ## Four firings per revolution pair, raised an octave so a laptop speaker can reproduce it.
        var pitch = self.rpm / 60.0 * 4.0
        var gain = 0.6 + 0.4 * level
        if self.main <> nil then
            self.main.freq(pitch).volume((0.05 + 0.10 * self.load) * gain)
            self.sub.freq(pitch * 0.5).volume((0.04 + 0.05 * self.load) * gain)
        end
    end
end
