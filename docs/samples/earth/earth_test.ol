## The astronomy of the Earth example, with no window: the Sun's position against the known dates of
## the equinoxes and solstices, and the turn of the globe. The pictures of the planet need a display:
## tests/gfx_earth_test.ol reads them.
## Run: ./build/ollin docs/samples/earth/earth_test.ol — it must finish without error.

import "astro.ol"

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

## ── from a direction to a place ────────────────────────────────────────────
## The Sun's own direction lands on the subsolar point, whatever the day, and the axis on the pole.
for day = 0, 360, 30 do
    var t = 9497 + day + 0.37
    var lx, ly, lz = sunLightDirection(t)
    var lat, lon = sceneToLatLon(-lx, -ly, -lz, t)
    var sunLat, sunLon = subsolarPoint(t)
    assert(near(lat, sunLat, 0.0001) and near(wrap180(lon - sunLon), 0, 0.0001))
end
var poleLat, poleLon = sceneToLatLon(0, math.cos(math.rad(TILT)), -math.sin(math.rad(TILT)), 9497)
assert(near(poleLat, 90, 0.01))
## The equinox direction lies on the equator, at the longitude the sidereal angle puts it.
var eqLat, eqLon = sceneToLatLon(1, 0, 0, 0)
assert(near(eqLat, 0, 0.0001) and near(eqLon, wrap180(-greenwichAngle(0)), 0.0001))
print("earth ok")
