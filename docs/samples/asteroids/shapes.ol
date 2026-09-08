## The LOOK of Ollin Asteroids: every object is an outline, a closed run of points in its own
## coordinates, drawn as a stroked polygon with no fill. That is the whole graphic style of the
## game, and it is why nothing here is an image — an outline can be turned and scaled by
## calculation, at any size, without a texture.
##
## The outlines are OURS: the arcade original's are its author's work. The shapes below are drawn
## to the same idea (a hollow ship, four irregular rocks, a two-decked saucer), not traced.
##
## A point list is FLAT — x, y, x, y — because that is what graphics.polygon reads.

## Every outline is given at radius 1 and SCALED at draw time. That is not a style choice: the
## scale then IS the object's collision radius, so the drawing and the collision test read the same
## number and cannot drift apart. An outline in pixels would have needed a second constant, and the
## two would have been multiplied together — the ship was drawn nine times too large that way.
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

## Turns an outline and moves it: the ONE conversion from an object's own coordinates to the
## field's. Both the drawing and the collision test read the same numbers, since a rock's radius is
## its scale and nothing else.
func placeShape(pts, x, y, ang, s)
    var c = math.cos(ang)
    var sn = math.sin(ang)
    var out = []
    for i = 1, #pts // 2 do
        var px = pts[i * 2 - 1] * s
        var py = pts[i * 2] * s
        out.push(x + px * c - py * sn)
        out.push(y + px * sn + py * c)
    end
    return out
end

## Draws an outline WRAPPED: an object straddling an edge must be seen on both sides, otherwise it
## would appear to vanish and reappear whole. The copies are drawn only when the object comes
## within its own radius of an edge, so the common case is one polygon.
func drawShape(pts, x, y, ang, s, w, h)
    var placed = placeShape(pts, x, y, ang, s)
    graphics.polygon(placed)
    var ox = 0
    var oy = 0
    if x < s then
        ox = w
    elseif x > w - s then
        ox = 0 - w
    end
    if y < s then
        oy = h
    elseif y > h - s then
        oy = 0 - h
    end
    if ox <> 0 then
        graphics.polygon(placeShape(pts, x + ox, y, ang, s))
    end
    if oy <> 0 then
        graphics.polygon(placeShape(pts, x, y + oy, ang, s))
    end
    if ox <> 0 and oy <> 0 then
        graphics.polygon(placeShape(pts, x + ox, y + oy, ang, s))
    end
end
