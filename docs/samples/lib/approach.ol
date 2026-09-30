## Brings `cur` towards `target` by a fraction of the distance left. The fraction depends on `dt`
## (the frame's duration, in seconds) through an exponential, so the result does not change with
## the frame rate, unlike a plain `cur + (target - cur) * 0.1`. `rate` is how eager it is: higher
## is sharper (the gap shrinks by a factor e every 1 / rate seconds).
##
##   import "../lib/approach.ol"
##   x = approach(x, wantedX, 6.0, deltaTime)
func approach(cur, target, rate, dt)
    return cur + (target - cur) * (1 - math.exp(-rate * dt))
end
