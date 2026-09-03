## A REUSABLE self-adapting view distance, for terrain streamed as chunks.
##
## It holds the current radius, its bounds, the manual mode and the self-adaptation. With vsync
## locked, deltaTime only reveals the headroom once frames overrun, so we measure the
## SHARE of slow frames over a window, against the display rate as MEASURED — a phone capped at
## 30 Hz keeps its computing power. Unreal frames, longer than STALL_DT, from a background tab or a
## resume, are ignored. It also carries three buttons at the top right: - and + switch to manual
## control, A switches back to self-adaptation.
##
## update() returns:   1 the radius has GROWN, so streaming is to be restarted,
##                    -1 the radius has SHRUNK, so the outer ring is to be unloaded,
##                     0 unchanged.
## hit() returns:      1 and -1 as above, 2 for a button consumed with no change, a bound having
##                     been reached, and 0 for outside the buttons, to be handled elsewhere, by the
##                     joystick for one.
##
## Wiring on the host's side:
##   import "view_distance.ol"
##   global vd = ViewDistance(4, 1, 24)       ## the fourth argument is the SEED rate, 60 by default;
##                                            ## the real rate is measured afterwards
##   func mouse.pressed(x, y)
##       var ev = vd.hit(x, y)
##       if ev == 1 then streaming = true
##       elseif ev == -1 then streamUnload(lastcx, lastcz, 0)
##       elseif ev == 0 then pad.press(x, y) end   ## ev == 2 means there is nothing to do
##   end
##   ## in draw(): loop over vd.radius, then
##   ##   var ev = vd.update(deltaTime, streaming)
##   ##   if ev == 1 then streaming = true elseif ev == -1 then streamUnload(pcx, pcz, 0) end
##   ##   ... vd.draw()  (the buttons)  ...  vd.mode() → "auto"/"manual"

class ViewDistance
    func init(start, lo, hi, fps = 60)
        self.radius = start
        self.lo = lo
        self.hi = hi          ## a safety net; the real limit comes from the frame rate and the memory
        self.manual = false
        ## The display rate is MEASURED, not assumed: a phone may cap at 30 Hz without its
        ## computing power being halved. With a threshold fixed at 60, every frame would look late
        ## and the radius would collapse to `lo`. `fps` is only a seed, replaced from the first
        ## window on by the rate VOTED for.
        ##
        ## A vote rather than the shortest frame: the browser sometimes delivers two images close
        ## together, catching up, and 2 % of such frames were enough to suggest a 120 Hz screen,
        ## hence to treat every normal frame as late. Here each plausible rate counts its frames
        ## "on time" (dt <= the period times MARGIN) and we keep the HIGHEST one that gathers
        ## VOTE_PART of them, so a few outliers weigh nothing.
        self.CAD = [120, 90, 60, 50, 40, 30]   ## the candidate rates, in decreasing order
        self.ok = [0, 0, 0, 0, 0, 0]           ## the frames on time for each candidate
        self.MARGIN = 1.25                     ## the tolerance on the period, hence the lateness threshold
        self.VOTE_PART = 0.7                   ## the share of frames on time needed to elect a rate
        self.hzKeep = fps                      ## the rate kept, seeded until the first vote
        self.voted = false                     ## has a rate been elected yet?
        self.miss = 0                          ## consecutive windows that do not confirm hzKeep
        ## A screen's rate hardly ever changes, so a drop in the vote is first put down to a
        ## passing overload: otherwise a rendering that falls behind would suggest a slower screen,
        ## and the radius would never pull back. It is adopted only after DEMOTE windows, the time
        ## a real cap needs to confirm itself.
        self.DEMOTE = 20
        self.STALL_DT = 0.30              ## an unreal frame, from a background tab or a resume
        self.WIN = 0.5
        ## A window must also hold enough frames: at 30 Hz, half a second gives only fifteen, and
        ## the share of slow frames becomes too noisy to decide on — a single late frame weighs 7 %
        ## there. So the window lengthens as the rate falls.
        self.MIN_N = 30
        self.GROW = 0.03      ## it only grows on VERY few slow frames, which keeps some headroom
        self.DROP = 0.25      ## a wide dead zone [GROW;DROP]: it does not chase the limit, nor oscillate
        self.RELAX = 20.0     ## retests the learnt ceiling rarely, which avoids oscillation
        self.MEM_MAX = 110000000
        self.t = 0.0
        self.n = 0
        self.slow = 0
        self.step = 1         ## a doubling climb: 1, 2, 4, 8…
        self.cap = 999        ## the ceiling learnt on a stall, released after RELAX seconds of stability
        self.good = start     ## the last radius confirmed smooth, to fall back to after an overshoot
        self.stable = 0.0
        self.BTN = 54
        self.BTN_Y = 40
        self.BTN_MARGIN = 12  ## the margin from the right edge
        self.GAP = 10         ## the gap between buttons
    end

    func mode()
        return self.manual and "manual" or "auto"
    end

    ## Adjusts the radius from the share of slow frames in the window just past. It measures
    ## neither during the baking of chunks nor in manual mode. Too many slow frames (> DROP)
    ## halves the way back to the last radius known good, and learns that ceiling; a fluid
    ## window (< GROW) climbs by doubling, and at the ceiling it lets go after RELAX. Between
    ## the two thresholds it holds.
    func update(dt, streaming)
        if dt <= 0 or dt >= self.STALL_DT or streaming or self.manual then
            return 0
        end
        self.t = self.t + dt
        self.n = self.n + 1
        for j, hz in self.CAD do
            if dt <= self.MARGIN / hz then
                self.ok[j] = self.ok[j] + 1
            end
        end
        if self.t < self.WIN or self.n < self.MIN_N then return 0 end
        ## The rate is elected over the SAME window as the one being judged: the late frames are
        ## exactly those not "on time" for that rate.
        var first = not self.voted
        self.slow = self.n - self.voteCadence()
        if first then
            self.t = 0.0                       ## the seed window: it served to elect the
            self.n = 0                         ## rate, and judging it would mean nothing
            self.slow = 0
            return 0
        end
        var memFull = mem() > self.MEM_MAX   ## read once per window, not every frame
        var ev = 0
        if (memFull or self.slow > self.n * self.DROP) and self.radius > self.lo then
            self.cap = self.radius - 1
            self.radius = math.clamp((self.good + self.radius) // 2, self.lo, self.radius - 1)
            self.step = 1
            self.stable = 0.0
            ev = -1
        elseif self.slow < self.n * self.GROW then
            self.good = self.radius
            if self.radius < self.hi and self.radius < self.cap and not memFull then
                self.radius = math.min(self.radius + self.step, math.min(self.hi, self.cap))
                self.step = self.step * 2
                self.stable = 0.0
                ev = 1
            else
                self.step = 1
                self.stable = self.stable + self.t
                if self.radius == self.cap and self.stable >= self.RELAX and not memFull then
                    self.cap = self.cap + 1
                    self.stable = 0.0
                end
            end
        else
            self.step = 1
            self.stable = 0.0
        end
        self.t = 0.0
        self.n = 0
        self.slow = 0
        return ev
    end

    ## Elects the window's rate and returns the number of frames on time for it. A rate lower than
    ## the one kept is adopted only after DEMOTE windows.
    func voteCadence()
        var vote = self.CAD[#self.CAD]
        var kept = self.ok[#self.CAD]
        for j, hz in self.CAD do
            if self.ok[j] >= self.n * self.VOTE_PART then
                vote = hz
                kept = self.ok[j]
                break
            end
        end
        if not self.voted then
            self.hzKeep = vote                 ## the first election: adopted as it stands,
            self.voted = true                  ## the seed would otherwise skew the very first judgement
            self.miss = 0
        elseif vote >= self.hzKeep then
            self.hzKeep = vote
            self.miss = 0
        else
            self.miss = self.miss + 1
            if self.miss >= self.DEMOTE then
                self.hzKeep = vote
                self.miss = 0
            end
        end
        ## The frames on time for the rate KEPT, not for the one voted: it is that rate which
        ## defines what being late means.
        var atTime = kept
        for j, hz in self.CAD do
            if hz == self.hzKeep then
                atTime = self.ok[j]
            end
            self.ok[j] = 0
        end
        return atTime
    end

    ## The display rate kept, in Hz, which can be shown while tuning.
    func hz()
        return self.hzKeep
    end

    ## The buttons line up from right to left: 0 is +, 1 is -, 2 is A.
    func btnX(i)   return W - self.BTN_MARGIN - self.BTN - i * (self.BTN + self.GAP) end

    ## Handles a press: + and - switch to manual and adjust the radius, within bounds; A switches
    ## back to self-adaptation. It returns 1 when the radius grew, -1 when it shrank, 2 for a button
    ## consumed with no change of radius, and 0 when no button was hit, to be handled elsewhere.
    func hit(x, y)
        if y < self.BTN_Y or y > self.BTN_Y + self.BTN then
            return 0
        end
        var xp = self.btnX(0)
        if x >= xp and x <= xp + self.BTN then
            self.manual = true
            if self.radius < self.hi then
                self.radius = self.radius + 1
                return 1
            end
            return 2
        end
        var xm = self.btnX(1)
        if x >= xm and x <= xm + self.BTN then
            self.manual = true
            if self.radius > self.lo then
                self.radius = self.radius - 1
                return -1
            end
            return 2
        end
        var xa = self.btnX(2)
        if x >= xa and x <= xa + self.BTN then
            self.manual = false
            return 2
        end
        return 0
    end

    func draw()
        ## [the button index, its label, the glyph's X nudge] — the "-" is narrower
        var btns = [[0, "+", -9], [1, "-", -6], [2, "A", -9]]
        var ty = self.BTN_Y + self.BTN / 2 - 16
        graphics.noStroke()
        for b in btns do
            var x = self.btnX(b[1])
            graphics.fill(Color(0, 0, 0, 0.38))
            if b[2] == "A" and not self.manual then
                graphics.fill(Color(0.30, 0.70, 1.00, 0.55))   ## a lit A means self-adaptation is on
            end
            graphics.rect(x, self.BTN_Y, self.BTN, self.BTN)
            graphics.stroke(colors.WHITE)
            graphics.fontSize(30)
            graphics.text(b[2], x + self.BTN / 2 + b[3], ty)
        end
    end
end
