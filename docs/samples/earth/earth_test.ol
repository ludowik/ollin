## The astronomy and the map of the Earth example, with no window: the Sun's position against the
## known dates of the equinoxes and solstices, the turn of the globe, and the properties of the
## procedural planet (it is the same every time, a third of it is land, its poles are ice).
## Run: ./build/ollin docs/samples/earth/earth_test.ol — it must finish without error.

import "astro.ol"
import "earth_map.ol"

func near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

## ── time ───────────────────────────────────────────────────────────────────
assert(unixToDays(J2000_UNIX) == 0)
assert(near(daysToUnix(unixToDays(1782043200)), 1782043200, 0.001))
var noon = date.utc(daysToUnix(9668))
assert(noon.year == 2026 and noon.month == 6 and noon.day == 21 and noon.hour == 12 and noon.minute == 0)
assert(date.utc(daysToUnix(9668.5)).hour == 0)         ## the fraction counts from noon: half a day later is midnight

assert(wrap360(-10) == 350 and wrap360(370) == 10 and wrap360(720) == 0)
assert(wrap180(190) == -170 and wrap180(-190) == 170 and wrap180(10) == 10)

## ── the Sun on the dates the almanac gives (UTC, to a few tenths of a degree) ──────────────────
## The tilt as the almanac gives it, written out: the program's own constant cannot be its own witness.
const TILT = 23.44

const MARCH_EQUINOX = 1774017960       ## 20 March 2026, 14:46
const JUNE_SOLSTICE = 1782030300       ## 21 June 2026, 08:25
const SEPTEMBER_EQUINOX = 1790121900   ## 23 September 2026, 00:05
const DECEMBER_SOLSTICE = 1797886200   ## 21 December 2026, 20:50

assert(near(wrap180(sunLongitude(unixToDays(MARCH_EQUINOX))), 0, 0.3))
assert(near(sunLongitude(unixToDays(JUNE_SOLSTICE)), 90, 0.3))
assert(near(sunLongitude(unixToDays(SEPTEMBER_EQUINOX)), 180, 0.3))
assert(near(sunLongitude(unixToDays(DECEMBER_SOLSTICE)), 270, 0.3))

assert(near(sunDeclination(unixToDays(MARCH_EQUINOX)), 0, 0.15))
assert(near(sunDeclination(unixToDays(SEPTEMBER_EQUINOX)), 0, 0.15))
assert(near(sunDeclination(unixToDays(JUNE_SOLSTICE)), TILT, 0.05))
assert(near(sunDeclination(unixToDays(DECEMBER_SOLSTICE)), -TILT, 0.05))

## Over a whole year the declination stays within the tilt of the axis, and does reach it.
var highest = -90
var lowest = 90
for day = 0, 365 do
    var d = sunDeclination(9497 + day)
    highest = math.max(highest, d)
    lowest = math.min(lowest, d)
end
assert(highest <= TILT + 0.01 and lowest >= -TILT - 0.01)
assert(highest > TILT - 0.2 and lowest < -TILT + 0.2)

## The right ascension follows the longitude, a quadrant at a time.
assert(near(wrap180(sunRightAscension(unixToDays(MARCH_EQUINOX))), 0, 0.3))
assert(near(sunRightAscension(unixToDays(JUNE_SOLSTICE)), 90, 0.4))
assert(near(sunRightAscension(unixToDays(SEPTEMBER_EQUINOX)), 180, 0.4))
assert(near(sunRightAscension(unixToDays(DECEMBER_SOLSTICE)), 270, 0.4))

## ── the globe ──────────────────────────────────────────────────────────────
assert(near(greenwichAngle(0), 280.46061837, 0.000001))
## a solar day later the Earth has turned a little more than a full turn
assert(near(greenwichAngle(1), wrap360(280.46061837 + 0.98564736629), 0.000001))
## and a sidereal day (23 h 56 min 4 s) brings it back to the same angle
assert(near(wrap180(greenwichAngle(0.99726957) - greenwichAngle(0)), 0, 0.001))

## At noon UTC at the equinox the Sun is nearly over Greenwich (the equation of time shifts it by up
## to four degrees), at no latitude to speak of; an hour later it has moved fifteen degrees west.
var lat, lon = subsolarPoint(unixToDays(1774008000))      ## 20 March 2026, 12:00
assert(near(lat, 0, 0.5) and near(lon, 0, 5))
var lat1, lon1 = subsolarPoint(unixToDays(1774008000) + 1 / 24)
assert(near(wrap180(lon1 - lon), -15.04, 0.1))

## At the June solstice at noon UTC it is over the Tropic of Cancer, on the Greenwich meridian or so.
var tropicLat, tropicLon = subsolarPoint(9668)
assert(near(tropicLat, TILT, 0.05) and near(tropicLon, 0, 3))

## The light travels from the Sun to the Earth: a unit vector, opposite to the Sun's direction. At
## the March equinox the Sun is in the direction of the equinox (+X), so the light goes towards −X.
var lx, ly, lz = sunLightDirection(unixToDays(MARCH_EQUINOX))
assert(near(lx * lx + ly * ly + lz * lz, 1, 0.000001))
assert(near(lx, -1, 0.01) and ly == 0 and near(lz, 0, 0.01))
## At the June solstice the Sun is at the scene's −Z: the light travels towards +Z.
var jx, jy, jz = sunLightDirection(unixToDays(JUNE_SOLSTICE))
assert(near(jz, 1, 0.01) and near(jx, 0, 0.01))

## ── the map ────────────────────────────────────────────────────────────────
math.noiseSeed(MAP_SEED)

var ux, uy, uz = unitVector(35, -120)
assert(near(ux * ux + uy * uy + uz * uz, 1, 0.000001))
var px, py, pz = unitVector(90, 0)
assert(near(px, 0, 0.000001) and near(py, 1, 0.000001) and near(pz, 0, 0.000001))

## The same point gives the same colour, whatever the order the points are visited in.
var r1, g1, b1 = earthColor(12.5, 77.5)
var r2, g2, b2 = earthColor(-40, -20)
var r3, g3, b3 = earthColor(12.5, 77.5)
assert(r1 == r3 and g1 == g3 and b1 == b3)
assert(r1 <> r2 or g1 <> g2 or b1 <> b2)

## A regular grid of the sphere: every colour is a valid colour, a third of the points are land at
## most and a fifth at least, and the clouds cover some of the sky, not all of it.
var land = 0
var total = 0
var cloudy = 0
var clear = 0
for i = 0, 35 do
    var lat = 87.5 - i * 5
    for j = 0, 71 do
        var lon = -177.5 + j * 5
        var r, g, b = earthColor(lat, lon)
        assert(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1)
        var cloud = cloudDensity(lat, lon)
        assert(cloud >= 0 and cloud <= 1)
        if cloud > 0.5 then cloudy += 1 end
        if cloud < 0.05 then clear += 1 end
        if elevation(lat, lon) >= 0 then
            land += math.cos(math.rad(lat))      ## the grid is denser near the poles: weigh by the area
        end
        total += math.cos(math.rad(lat))
    end
end
assert(land / total > 0.2 and land / total < 0.4)
assert(cloudy > 0 and clear > cloudy)

## The poles are ice, the middle of a deep ocean is dark blue.
var ir, ig, ib = earthColor(89, 40)
assert(ir > 0.85 and ig > 0.85 and ib > 0.9)
var sr, sg, sb = earthColor(-89, -150)
assert(sr > 0.85 and sg > 0.85 and sb > 0.9)
var deep = 0
for lon = -180, 175, 5 do
    if elevation(0, lon) < -0.3 then
        var dr, dg, db = earthColor(0, lon)
        assert(db > dr and db > dg and db < 0.5)
        deep += 1
    end
end
assert(deep > 0)

## Another seed makes another planet.
math.noiseSeed(MAP_SEED + 1)
var other = 0
for lon = -180, 175, 5 do
    if elevation(10, lon) < 0 then other += 1 end
end
math.noiseSeed(MAP_SEED)
var same = 0
for lon = -180, 175, 5 do
    if elevation(10, lon) < 0 then same += 1 end
end
assert(other <> same)
print("earth ok")
