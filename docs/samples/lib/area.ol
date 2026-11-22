## The rectangles of a screen, the size of the area they were laid out for, and the height a field takes from the shape of the area.

func rectOf(x, y, w, h)
    return {x: x, y: y, w: w, h: h}
end

func inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

## The first of a list of rectangles that holds the point, or nil.
func rectAt(list, x, y)
    for r in list do
        if inRect(x, y, r) then
            return r
        end
    end
    return nil
end

## The height of a field `fieldW` wide for an area of w x h pixels: as tall as the shape of the area asks, within `low` and `high`, so that
## a tall screen is filled and a wide one is not stretched. An area with no width yet gets `low`.
func fitHeight(fieldW, w, h, low, high)
    if w <= 0 then
        return low
    end
    return math.floor(math.clamp(fieldW * h / w, low, high))
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
