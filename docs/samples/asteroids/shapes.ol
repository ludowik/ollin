## The LOOK of Ollin Asteroids: every object is an outline, a closed run of points in its own
## coordinates, drawn as a stroked polygon with no fill. That is the whole graphic style of the
## game, and it is why nothing here is an image — an outline can be turned and scaled by
## calculation, at any size, without a texture.
##
## The outlines are OURS: the arcade original's are its author's work. The shapes below are drawn
## to the same idea (a hollow ship, four irregular rocks, a two-decked saucer), not traced.
##
## A point list is FLAT — x, y, x, y — because that is what graphics.polygon reads.

## Every outline is given at radius 1, and the scale it is drawn at IS the object's collision
## radius, so a rock's size names one number and not two.
##
## The ship: a slim triangle with a notched tail, nose pointing along +x (angle zero).
const SHIP = [1.4, 0.0, -1.0, 0.9, -0.6, 0.0, -1.0, -0.9]
## The flame, drawn only while thrusting, and behind the notch so the two never touch.
const FLAME = [-0.6, 0.4, -1.5, 0.0, -0.6, -0.4]

## Four rocks, each a ring of unit radii sampled at twelve angles. ONE outline therefore serves the
## three sizes — the small rock is the large one seen closer, exactly as the original's was.
const ROCKS = [
    [1.0, 0.0, 0.62, 0.36, 0.5, 0.87, 0.0, 1.05, -0.45, 0.78, -0.9, 0.52, -1.0, 0.0, -0.78, -0.45,
     -0.4, -0.7, 0.0, -0.85, 0.55, -0.95, 0.9, -0.52],
    [0.95, 0.0, 0.78, 0.45, 0.35, 0.6, 0.0, 0.9, -0.5, 0.87, -0.85, 0.49, -1.05, 0.0, -0.6, -0.35,
     -0.5, -0.87, 0.0, -1.0, 0.45, -0.78, 0.87, -0.5],
    [0.85, 0.0, 0.65, 0.38, 0.55, 0.95, 0.0, 0.8, -0.52, 0.9, -0.95, 0.55, -0.8, 0.0, -0.9, -0.52,
     -0.35, -0.6, 0.0, -0.95, 0.5, -0.87, 1.0, -0.58],
    [1.05, 0.0, 0.58, 0.34, 0.45, 0.78, 0.0, 0.95, -0.4, 0.69, -0.87, 0.5, -0.95, 0.0, -0.69, -0.4,
     -0.55, -0.95, 0.0, -0.75, 0.6, -1.04, 0.8, -0.46]
]

## The saucer: two hulls, so it reads as a flying object rather than a lens. Given at radius 1 in
## width, like the rocks, and scaled to the big or the small ship.
const SAUCER      = [1.0, 0.0, 0.45, 0.42, -0.45, 0.42, -1.0, 0.0, -0.45, -0.3, 0.45, -0.3]
const SAUCER_DECK = [-0.45, -0.3, -0.22, -0.62, 0.22, -0.62, 0.45, -0.3]

## Sizes an outline ONCE, at startup. The scales the game uses are a fixed handful — three rock
## radii, the ship, its icon, the two saucers — so scaling belongs to the loading and not to the
## frame. Two reasons it is done here rather than by graphics.scale in the matrix: a scaled matrix
## would multiply the STROKE width with the shape, giving the large rock a fat outline and the
## small one a hairline; and a per-frame rebuild allocated one throwaway array per object per
## frame, up to four for an object straddling an edge.
func scaleShape(pts, s)
    var out = []
    for i = 1, #pts do
        out.push(pts[i] * s)
    end
    return out
end

## Draws a sized outline turned and placed by the ENGINE's matrix stack — the same points every
## frame, no arithmetic and no allocation in the script. `closed` says whether the run of points
## comes back on itself: an open one (the flame, the saucer's deck) is a polyline. One place drives
## the matrix stack, so no caller has to remember to pop it.
func drawAt(pts, x, y, ang, closed)
    graphics.pushMatrix()
    graphics.translate(x, y)
    graphics.rotate(math.deg(ang))
    if closed then
        graphics.polygon(pts)
    else
        graphics.polyline(pts)
    end
    graphics.popMatrix()
end

## Draws an outline WRAPPED: an object straddling an edge must be seen on both sides, otherwise it
## would appear to vanish and reappear whole. The copies are drawn only when the object comes
## within `margin` of an edge — its own radius — so the common case is one polygon.
func drawWrapped(pts, x, y, ang, margin, w, h)
    drawAt(pts, x, y, ang, true)
    var ox = 0
    var oy = 0
    if x < margin then
        ox = w
    elseif x > w - margin then
        ox = -w
    end
    if y < margin then
        oy = h
    elseif y > h - margin then
        oy = -h
    end
    if ox <> 0 then
        drawAt(pts, x + ox, y, ang, true)
    end
    if oy <> 0 then
        drawAt(pts, x, y + oy, ang, true)
    end
    if ox <> 0 and oy <> 0 then
        drawAt(pts, x + ox, y + oy, ang, true)
    end
end
