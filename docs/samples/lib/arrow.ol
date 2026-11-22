## The triangle of an arrow button: the flat list of points for graphics.polygon.

## The points of a triangle pointing "up", "down", "left" or "right", centred on (cx, cy), 2 * k wide and 2 * k high.
func arrowPoints(dir, cx, cy, k)
    if dir == "up" then
        return [cx, cy - k, cx - k, cy + k, cx + k, cy + k]
    elseif dir == "down" then
        return [cx, cy + k, cx - k, cy - k, cx + k, cy - k]
    elseif dir == "left" then
        return [cx - k, cy, cx + k, cy - k, cx + k, cy + k]
    end
    return [cx + k, cy, cx - k, cy - k, cx - k, cy + k]
end
