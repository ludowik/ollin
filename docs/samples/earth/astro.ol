## The astronomy of the Earth–Sun pair, in a few formulas: where the Sun is in the sky of the Earth on
## a given day, and how the globe is turned at a given hour. They are the low-precision formulas of the
## Astronomical Almanac, good to a few hundredths of a degree for the years around ours — far more
## than a picture needs, and it keeps the code short.
##
## TIME is a number of DAYS since 1 January 2000 at 12:00 UTC (the epoch called J2000), fractions
## included: 0.5 is midnight, 9668.0 is noon on 21 June 2026. One number, so the simulation advances by
## adding to it, and the calendar only shows up when it has to be displayed (date.utc does that).
##
## The frame of the scene, which the host uses as well: Y is the ecliptic's north, X the direction of
## the March equinox, and the Earth's axis leans away from Y by the obliquity, towards −Z. The Sun,
## seen from the Earth, is at (cos λ, 0, −sin λ), λ being its ecliptic longitude.

global OBLIQUITY = 23.4393      ## the tilt of the Earth's axis, in degrees
global J2000_UNIX = 946728000   ## 1 January 2000, 12:00 UTC, in seconds since 1970

func wrap360(a)
    return a - 360 * math.floor(a / 360)
end

## The same angle brought into [-180, 180[.
func wrap180(a)
    return wrap360(a + 180) - 180
end

func unixToDays(seconds)
    return (seconds - J2000_UNIX) / 86400
end

func daysToUnix(days)
    return J2000_UNIX + days * 86400
end

## The ecliptic longitude of the Sun, in degrees [0, 360[: 0 at the March equinox, 90 at the June
## solstice. The mean longitude advances by a degree a day, and the equation of the centre adds the
## unevenness of the Earth's elliptical orbit (the Sun runs faster in January than in July).
func sunLongitude(days)
    var meanLongitude = 280.460 + 0.9856474 * days
    var anomaly = 357.528 + 0.9856003 * days
    return wrap360(meanLongitude + 1.915 * math.sin(math.rad(anomaly)) + 0.020 * math.sin(math.rad(2 * anomaly)))
end

## The Sun's declination: the latitude where it stands at the zenith at noon, in degrees.
func sunDeclination(days)
    return math.deg(math.asin(math.sin(math.rad(OBLIQUITY)) * math.sin(math.rad(sunLongitude(days)))))
end

## The Sun's right ascension, in degrees [0, 360[: its position along the celestial equator.
func sunRightAscension(days)
    var lam = math.rad(sunLongitude(days))
    return wrap360(math.deg(math.atan2(math.cos(math.rad(OBLIQUITY)) * math.sin(lam), math.cos(lam))))
end

## The Greenwich mean sidereal time, in degrees [0, 360[: the angle between the March-equinox direction
## and the Greenwich meridian. The Earth turns 360.9856° a day, a little more than a turn, since it
## must make up for the angle the Sun moved through in the meantime.
func greenwichAngle(days)
    return wrap360(280.46061837 + 360.98564736629 * days)
end

## Where the Sun is at the zenith: its latitude (the declination) and its longitude, positive to the
## east, in degrees. The point lit head-on, the centre of the day side.
func subsolarPoint(days)
    return sunDeclination(days), wrap180(sunRightAscension(days) - greenwichAngle(days))
end

## The direction the Sun's light travels in, in the scene's frame: from the Sun towards the Earth.
func sunLightDirection(days)
    var lam = math.rad(sunLongitude(days))
    return -math.cos(lam), 0, math.sin(lam)
end
