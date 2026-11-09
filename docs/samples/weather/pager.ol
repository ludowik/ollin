## The motion of pages laid side by side, one screen wide each, numbered from 1: the page shown is a position that is
## fractional while a finger drags it or a slide is under way (2.5 is half of page 2 and half of page 3). Pure
## functions, so that weather_test.ol can try them without a screen.

const EDGE = 0.3                ## how far past the first and the last page a finger may pull, in pages
const FLICK = 0.3               ## seconds of the speed at release that count as more travel
const WINDOW = 0.1              ## seconds of the finger's path that its speed is read from
const FOLLOW = 45               ## the same spring while a finger holds the pages: stiff, so that it only evens out the steps of a touch that reports in jumps
const STIFF = 14                ## the slide is a critically damped spring: this is its rate (1/s), the gap shrinking as e^(-STIFF t)

## The position while a finger that took the pages at `grabX` (when they were at `grabPos`) is now at `x`, on a screen
## `width` wide: the pages follow the finger, and the ends give a little.
func dragPos(grabPos, grabX, x, width, last)
    return math.clamp(grabPos - (x - grabX) / width, 1 - EDGE, last + EDGE)
end

## The page a release settles on: the nearest one to where the finger would carry the pages (the speed is in pages per
## second), and never more than one page from where the drag began.
func pageAfterDrag(pos, speed, from, last)
    var wanted = math.floor(pos + speed * FLICK + 0.5)
    return math.clamp(wanted, math.max(1, from - 1), math.min(last, from + 1))
end

## Adds the position of the pages at the time `t` to `trail`, the samples of the drag, and gives the speed of the last
## WINDOW seconds in pages per second: a few frames of a quick flick tell its speed better than a running average, which
## has not caught up when the finger lifts, and a finger that stopped before it lifted reads as still.
func track(trail, t, pos)
    trail.push([t, pos])
    while len(trail) > 1 and t - trail[1][1] > WINDOW do
        trail.dequeue()
    end
    var first = trail[1]
    if t - first[1] < 0.001 then
        return 0
    end
    return (pos - first[2]) / (t - first[1])
end

## The speed (pages per second) a slide starts with: the one the finger left, unless it would carry the pages past the
## page they settle on, which a spring that is not allowed to overshoot cannot do.
func launch(pos, speed, target)
    var room = math.abs(target - pos) * STIFF
    if target > pos then
        return math.min(speed, room)
    end
    return math.max(speed, -room)
end

## One frame of the slide towards a position: the position and the speed after `dt` seconds. A critically damped spring in
## closed form, so that it carries the speed of the finger on and stays exact whatever the length of the frame. `stiff`
## is the rate of the spring, STIFF by default.
func slide(pos, speed, target, dt, stiff = 0)
    var rate = stiff > 0 and stiff or STIFF
    var gap = pos - target
    if math.abs(gap) < 0.0005 and math.abs(speed) < 0.01 then
        return target, 0
    end
    var carry = speed + rate * gap
    var fade = math.exp(-rate * dt)
    return target + (gap + carry * dt) * fade, (carry - rate * (gap + carry * dt)) * fade
end

## The two pages whose skies the screen blends at a position, and how much of the second: the sky does not slide with
## the pages, it changes colour from one to the next, and holds at the ends where a drag pulls past them.
func skyBetween(pos, last)
    var first = math.clamp(math.floor(pos), 1, last)
    return first, math.min(first + 1, last), math.clamp(pos - first, 0, 1)
end
