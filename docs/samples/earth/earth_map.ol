## A PROCEDURAL Earth: no image file, no dataset. The continents are the places where a fractal noise
## rises above the sea, and the climate is read from the latitude, the altitude and a second noise
## for the moisture. It is not our planet's map — it is a planet that looks like ours — and that
## is on purpose: the whole globe is computed from nothing, the same way each time.
##
## Everything here is a PURE function of a point on the sphere, given as a latitude and a longitude
## in degrees. The noise is sampled in three dimensions, at the point's position on the unit sphere:
## a map drawn from (longitude, latitude) alone would show a seam at ±180° and a pinch at the poles.
##
## The host fills its textures row by row from these functions (earth.ol), and the test
## (earth_test.ol) checks them without any window.

global MAP_SEED = 7
global SEA_LEVEL = 0.575    ## the noise value above which there is land: 30 % of the sphere or so
global ICE_LATITUDE = 71    ## where the polar caps begin on average, in degrees

func mix(a, b, t)
    return a + (b - a) * t
end

func smoothstep(lo, hi, x)
    var t = math.clamp((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)
end

## Two colours mixed: t = 0 gives the first, t = 1 the second.
func mixColor(r1, g1, b1, r2, g2, b2, t)
    return mix(r1, r2, t), mix(g1, g2, t), mix(b1, b2, t)
end

## A colour, lit by `grain`, and kept within [0, 1]: a channel above 1 would wrap round when it is stored
## in an image, and a snowy peak would come out dark.
func shade(r, g, b, grain)
    return math.min(1, r * grain), math.min(1, g * grain), math.min(1, b * grain)
end

## The unit vector of a point of the sphere. y is the polar axis.
func unitVector(lat, lon)
    var phi = math.rad(lat)
    var lam = math.rad(lon)
    return math.cos(phi) * math.cos(lam), math.sin(phi), math.cos(phi) * math.sin(lam)
end

## How high the ground is at a point: negative under the sea, 0 at the shore, 1 at the highest peaks.
func elevation(lat, lon)
    var x, y, z = unitVector(lat, lon)
    var n = math.noise(x * 1.5 + 11, y * 1.5 + 5, z * 1.5 + 3)
    if n < SEA_LEVEL then
        return (n - SEA_LEVEL) / SEA_LEVEL
    end
    return math.min((n - SEA_LEVEL) / 0.275, 1)
end

## How wet the ground is, from 0 (desert) to 1 (rainforest): a noise, dried out in the subtropical
## belts where the real deserts are, and wetter around the equator.
func moisture(lat, lon)
    var x, y, z = unitVector(lat, lon)
    var m = math.noise(x * 2.6 + 30, y * 2.6 + 20, z * 2.6 + 10)
    var belt = math.abs(math.abs(lat) - 25) / 10
    m -= 0.28 * math.exp(-belt * belt)
    m += 0.18 * math.exp(-(lat * lat) / 400)
    return m
end

## The colour of the surface at a point: red, green and blue in [0, 1].
func earthColor(lat, lon)
    var x, y, z = unitVector(lat, lon)
    var e = elevation(lat, lon)
    var grain = 0.92 + 0.16 * math.noise(x * 14 + 5, y * 14 + 9, z * 14 + 2)   ## fine variations, so no area is flat
    var latAbs = math.abs(lat)
    ## The polar caps: their edge wanders with a noise, so it is not a parallel.
    var edge = ICE_LATITUDE + 12 * (math.noise(x * 3 + 70, y * 3 + 70, z * 3 + 70) - 0.5)
    if latAbs > edge then
        return shade(0.93, 0.96, 1.0, 0.9 + 0.1 * grain)
    end
    if e < 0 then
        ## the sea: darker as it gets deeper, with a bright shelf along the coasts
        var shallow = smoothstep(-0.30, 0, e)
        var r = mix(0.02, 0.10, shallow)
        var g = mix(0.08, 0.38, shallow)
        var b = mix(0.25, 0.62, shallow)
        return shade(r, g, b, grain)
    end
    ## the land: a biome from the temperature and the moisture, then the relief on top
    var temp = 1 - latAbs / 90 - e * 0.5
    var wet = moisture(lat, lon)
    ## Each biome takes over from the previous one over a short stretch of moisture, so the borders are
    ## gradients rather than staircases.
    var r, g, b = 0.80, 0.68, 0.43                                                     ## desert
    r, g, b = mixColor(r, g, b, 0.62, 0.60, 0.28, smoothstep(0.34, 0.38, wet))         ## savanna
    r, g, b = mixColor(r, g, b, 0.24, 0.50, 0.17, smoothstep(0.44, 0.48, wet))         ## grassland
    r, g, b = mixColor(r, g, b, 0.09, 0.34, 0.12, smoothstep(0.56, 0.60, wet))         ## forest
    var tr, tg, tb = mixColor(0.50, 0.52, 0.46, 0.16, 0.32, 0.22, smoothstep(0.43, 0.47, wet))   ## tundra, then taiga
    r, g, b = mixColor(r, g, b, tr, tg, tb, 1 - smoothstep(0.26, 0.34, temp))
    var shore = 1 - smoothstep(0, 0.04, e)
    r = mix(r, 0.82, shore * 0.8)               ## a strip of sand along the sea
    g = mix(g, 0.74, shore * 0.8)
    b = mix(b, 0.50, shore * 0.8)
    var rock = smoothstep(0.30, 0.65, e)
    r = mix(r, 0.44, rock)
    g = mix(g, 0.40, rock)
    b = mix(b, 0.36, rock)
    var snow = smoothstep(0.70, 0.90, e + (0.5 - temp) * 0.3)
    r = mix(r, 0.95, snow)
    g = mix(g, 0.96, snow)
    b = mix(b, 1.00, snow)
    return shade(r, g, b, grain)
end

## The cloud cover at a point, from 0 (clear) to 1 (thick): a noise, favoured along the equator and
## in the storm tracks near 50° — and kept thin elsewhere, so the sea and the land stay readable.
func cloudDensity(lat, lon)
    var x, y, z = unitVector(lat, lon)
    var c = math.noise(x * 3.2 + 90, y * 4.2 + 40, z * 3.2 + 60)
    var a = math.abs(lat)
    var bias = 0.07 * math.exp(-(a * a) / 300) + 0.06 * math.exp(-((a - 50) * (a - 50)) / 200)
    return smoothstep(0.50, 0.72, c + bias)
end
