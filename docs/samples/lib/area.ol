## The rectangles of a screen, and the size of the area they were laid out for.

func rectOf(x, y, w, h)
    return {x: x, y: y, w: w, h: h}
end

func inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

## True when W or H differ from the area `cache` (a map with w and h) was laid out for, which it then remembers: what depends
## on the area alone is computed again only then.
func areaChanged(cache)
    if W == cache.w and H == cache.h then
        return false
    end
    cache.w = W
    cache.h = H
    return true
end
