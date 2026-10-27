## The real pictures of the Earth example: they are laid out for the sphere's mesh (latitude along x, 0 at
## the north pole; longitude along y, west to east), and show the Earth where it should be. A flipped or
## shifted file would still load, so this reads known places back. It needs a window and a GL context, so
## it runs under Xvfb with the raylib build (tests/run_gfx.sh).

const GROUND = "../docs/samples/earth/earth_day.jpg"
const CLOUDS = "../docs/samples/earth/earth_clouds.png"
const NIGHT = "../docs/samples/earth/earth_night.jpg"

func setup()
    graphics.canvas(32, 32, "earth test")
end

## The colour of a place, read where the layout puts it.
func place(img, lat, lon)
    var x = math.floor((90 - lat) / 180 * img.width)
    var y = math.floor((lon + 180) / 360 * img.height)
    var r, g, b, a = image.getPixel(img, x, y)
    return r, g, b, a
end

## The mean brightness of a box of latitudes and longitudes, sampled every two degrees.
func glow(img, lat0, lat1, lon0, lon1)
    var total = 0
    var count = 0
    for lat = lat0, lat1, 2 do
        for lon = lon0, lon1, 2 do
            var r, g, b = place(img, lat, lon)
            total += (r + g + b) / 3
            count += 1
        end
    end
    return total / count
end

func draw()
    var ground = image.load(GROUND)
    assert(ground.width == 2048 and ground.height == 4096)

    var r, g, b = place(ground, 23, 12)          ## the Sahara: sand
    assert(r > b + 0.15 and r > 0.45)
    r, g, b = place(ground, 0, -140)             ## the Pacific: dark water
    assert(b > r and r + g + b < 1)
    r, g, b = place(ground, 75, -40)             ## Greenland: ice
    assert(r > 0.7 and g > 0.7 and b > 0.7)
    r, g, b = place(ground, -85, 0)              ## Antarctica: ice
    assert(r > 0.7 and g > 0.7 and b > 0.7)
    r, g, b = place(ground, -5, -62)             ## the Amazon: forest
    assert(g > r and g > b)
    r, g, b = place(ground, 48, 2)               ## France: land, not the dark blue of the sea
    assert(r + g + b > 0.35 and r >= b)

    var clouds = image.load(CLOUDS)
    assert(clouds.width == 1536 and clouds.height == 3072)
    var covered = 0
    var clear = 0
    for x = 0, clouds.width - 1, 8 do
        for y = 0, clouds.height - 1, 8 do
            var cr, cg, cb, ca = image.getPixel(clouds, x, y)
            if ca > 0.3 then covered += 1 end
            if ca < 0.05 then clear += 1 end
        end
    end
    assert(covered > 0 and clear > covered)      ## a cloud cover has gaps, and is not empty
    ## The lights of the cities, on black: Europe and Japan shine, the ocean, the Sahara and the ice do not.
    var night = image.load(NIGHT)
    assert(night.width == 1024 and night.height == 2048)
    var europe = glow(night, 44, 54, -5, 15)
    assert(europe > 0.05 and glow(night, 33, 40, 132, 142) > 0.05)
    assert(glow(night, -10, 10, -160, -120) < 0.005 and glow(night, 18, 28, 0, 20) < 0.005)
    assert(glow(night, -85, -75, -60, 60) < 0.005)
    r, g, b = place(night, 48.9, 2.4)
    assert(r >= b)                                ## warm, not blue
    image.unload(night)

    image.unload(ground)
    image.unload(clouds)
    graphics.quit()
end
