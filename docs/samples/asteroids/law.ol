## The field's one law: everything wraps. Written once and applied to every moving thing, so nothing can be forgotten on one
## object and leave it flying off into nowhere.

## math.frac is x - floor(x), so it is never negative: one expression brings a coordinate back into the field whatever it left
## by. Two subtractions only put back an object that overshot by LESS than a field, which a dropped frame is enough to break.
func wrap(o)
    o.x = math.frac(o.x / FIELD_W) * FIELD_W
    o.y = math.frac(o.y / FIELD_H) * FIELD_H
end

## The distance between two points on a wrapped field is the SHORTEST of the ways round. Ignoring
## that made a shot pass through a rock straddling an edge, the two being a field apart by their
## coordinates and a few pixels apart on the screen.
func near(ax, ay, bx, by, r)
    var dx = math.abs(ax - bx)
    var dy = math.abs(ay - by)
    if dx > FIELD_W / 2 then
        dx = FIELD_W - dx
    end
    if dy > FIELD_H / 2 then
        dy = FIELD_H - dy
    end
    return dx * dx + dy * dy <= r * r
end

func advance(o, dt)
    o.x += o.vx * dt
    o.y += o.vy * dt
    wrap(o)
end
