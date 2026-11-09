## The motion of pages laid side by side, one screen wide each, numbered from 1: the page shown is a position that is
## fractional while a finger drags it or a slide is under way (2.5 is half of page 2 and half of page 3). Pure
## functions, so that weather_test.ol can try them without a screen.

const EDGE = 0.3                ## how far past the first and the last page a finger may pull, in pages
const FLICK = 0.2               ## seconds of the speed at release that count as more travel
const SLIDE = 12                ## how fast a slide closes the gap: a fraction of it per second

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

## One frame of the slide towards a page.
func slide(pos, target, dt)
    var gap = target - pos
    if math.abs(gap) < 0.001 then
        return target
    end
    return pos + gap * math.min(1, dt * SLIDE)
end
