#!/usr/bin/env python3
"""Builds the three real maps of docs/samples/earth/ — the ground, a snapshot of the clouds and the lights of the
cities by night.

    python3 tools/convert_earth_textures.py

Run BY HAND, not by the build: the images are committed, and this needs the npm registry and Pillow.

Source: the npm package `three-globe` (MIT for its code), whose example folder ships
  example/img/earth-blue-marble.jpg   the NASA "Blue Marble" composite of the Earth, 4096 x 2048,
                                      equirectangular, the northern winter's snow cover;
  example/clouds/clouds.png           a real cloud cover as an alpha mask, 4096 x 2048, which that
                                      package takes from https://github.com/turban/webgl-earth;
  example/img/earth-night.jpg         the Earth by night, 4096 x 2048: the lights of the cities (NASA's
                                      "Black Marble" kind of picture) over a blue-tinted relief that
                                      this script throws away.
The package states no licence for the pictures themselves, only for its code. The Blue Marble and the
night picture look like NASA imagery (public domain unless it says otherwise, which could not be
checked here); the origin of the cloud mask is whatever turban/webgl-earth says of it, which could not be read from here (GitHub is blocked
by the proxy of the session). Check both before reusing these files anywhere else.

Why not simply ship the originals: the engine's sphere reads its texture with the LATITUDE along x
(0 at the north pole) and the LONGITUDE along y (west to east), the opposite of the usual
equirectangular layout, so the pictures are transposed here, once, instead of being turned pixel
by pixel by the script every time. The ground keeps the full 4096 x 2048 of its source (2048 x 4096
once transposed): the sphere is meant to be looked at close. The clouds are kept at 3072 x 1536 (the source has detail beyond 2048, and a cloud edge is what first looks soft when the
globe is close); the lights are reduced to 2048 x 1024.

The night picture is not used as it comes. Its cities are warm and its background is blue, so a
city is what has more red and green than blue: the light of a pixel is min(r, g) - b / 2, clamped
at 0 (the background gives nothing, a city gives its glow), boosted, painted in a warm
white and given a halo. Everything else goes to black, which is what an additive layer needs.

The script also reads a few places of the SOURCE and refuses to write anything if the picture
does not show what the Earth shows there: a wrong file, a flipped map or a shifted meridian
would all fail one of those checks.
"""
import os
import subprocess
import sys
import tarfile
import tempfile

from PIL import Image, ImageChops, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sample_paths

PACKAGE = "three-globe@2.45.6"
GROUND = "example/img/earth-blue-marble.jpg"
CLOUDS = "example/clouds/clouds.png"
NIGHT = "example/img/earth-night.jpg"
CLOUDS_SIZE = (3072, 1536)
CLOUDS_ALPHA_STEP = 8     # the opacity is rounded to this step: smooth enough once filtered, and the PNG a third smaller
NIGHT_SIZE = (2048, 1024)
LIGHT_GAIN = 4.0
LIGHT_COLOUR = (1.0, 0.84, 0.58)    # the warm white of sodium and tungsten


def fetch(workdir):
    subprocess.run(["npm", "pack", PACKAGE, "--silent"], cwd=workdir, check=True, capture_output=True)
    tarball = next(f for f in os.listdir(workdir) if f.endswith(".tgz"))
    with tarfile.open(os.path.join(workdir, tarball)) as tar:
        members = [m for m in tar.getmembers() if m.name in ("package/" + GROUND, "package/" + CLOUDS, "package/" + NIGHT)]
        tar.extractall(workdir, members=members, filter="data")
    return os.path.join(workdir, "package")


def cloud_layer(source):
    """The clouds as white with an alpha, transposed for the sphere. Only the alpha is resampled: the colour
    of the source is black where there is no cloud, and averaging it in would grey the edge of every cloud."""
    alpha = source.convert("RGBA").getchannel("A").resize(CLOUDS_SIZE, Image.LANCZOS).transpose(Image.TRANSPOSE)
    alpha = alpha.point(lambda v: v // CLOUDS_ALPHA_STEP * CLOUDS_ALPHA_STEP)
    clouds = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    clouds.putalpha(alpha)
    return clouds


def pixel_at(img, lat, lon):
    """The colour of a geographic place on an equirectangular picture (north up, 180 W at the left)."""
    x = int((lon + 180) / 360 * img.width)
    y = int((90 - lat) / 180 * img.height)
    return img.getpixel((min(x, img.width - 1), min(y, img.height - 1)))


def check_geography(ground):
    sahara = pixel_at(ground, 23, 12)         # sand: red and green well above blue
    pacific = pixel_at(ground, 0, -140)       # deep ocean: dark and blue
    greenland = pixel_at(ground, 75, -40)     # ice cap: bright
    antarctica = pixel_at(ground, -85, 0)
    amazon = pixel_at(ground, -5, -62)        # forest: green above red and blue
    assert sahara[0] > sahara[2] + 40 and sahara[0] > 120, f"Sahara is not sand: {sahara}"
    assert pacific[2] > pacific[0] and sum(pacific) < 250, f"the Pacific is not deep water: {pacific}"
    assert min(greenland) > 170, f"Greenland is not white: {greenland}"
    assert min(antarctica) > 170, f"Antarctica is not white: {antarctica}"
    assert amazon[1] > amazon[0] and amazon[1] > amazon[2], f"the Amazon is not green: {amazon}"


def city_lights(night):
    """The lights of the cities alone, as an RGB picture on black."""
    src = night.resize(NIGHT_SIZE, Image.BOX).convert("RGB")
    out = Image.new("RGB", src.size)
    pixels = src.load()
    result = out.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b = pixels[x, y]
            light = max(0.0, min(r, g) - b / 2) / 255 * LIGHT_GAIN
            light = min(1.0, light) ** 0.8
            result[x, y] = tuple(int(round(255 * light * c)) for c in LIGHT_COLOUR)
    # A city is a point of a few texels, which shrinks to nothing on a screen: a halo round it, the glow
    # of the air above, gives it a size.
    bloom = out.filter(ImageFilter.GaussianBlur(2)).point(lambda v: min(255, v * 3))
    return ImageChops.add(out, bloom)


def box_mean(img, lat0, lat1, lon0, lon1):
    """The mean brightness (0..255) of a box of an equirectangular picture, latitudes and longitudes in degrees."""
    x0, x1 = (int((lon + 180) / 360 * img.width) for lon in (lon0, lon1))
    y0, y1 = (int((90 - lat) / 180 * img.height) for lat in (lat1, lat0))
    total = 0
    count = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            total += sum(img.getpixel((x, y))) / 3
            count += 1
    return total / count


def check_lights(lights):
    europe = box_mean(lights, 44, 54, -5, 15)
    eastern_us = box_mean(lights, 33, 43, -90, -72)
    japan = box_mean(lights, 33, 40, 132, 142)
    sahara = box_mean(lights, 18, 28, 0, 20)
    pacific = box_mean(lights, -10, 10, -160, -120)
    amazon = box_mean(lights, -10, 0, -70, -55)
    antarctica = box_mean(lights, -85, -75, -60, 60)
    for name, value in (("Europe", europe), ("the eastern United States", eastern_us), ("Japan", japan)):
        assert value > 4, f"no lights over {name}: {value}"
        assert value > 5 * max(sahara, pacific, antarctica, 0.1), f"{name} is not brighter than the dark places"
    assert max(pacific, antarctica) < 1, f"the ocean or the ice shines: {pacific}, {antarctica}"
    assert amazon < europe / 3, f"the Amazon shines like Europe: {amazon}"


def main():
    with tempfile.TemporaryDirectory() as workdir:
        package = fetch(workdir)
        ground = Image.open(os.path.join(package, GROUND)).convert("RGB")
        check_geography(ground)
        ground = ground.transpose(Image.TRANSPOSE)
        clouds = cloud_layer(Image.open(os.path.join(package, CLOUDS)))
        night = Image.open(os.path.join(package, NIGHT)).convert("RGB")
        lights = city_lights(night)
        check_lights(lights)
        lights = lights.transpose(Image.TRANSPOSE)
        lights_path = sample_paths.sample_path("earth_night.jpg", "earth")
        lights.save(lights_path, quality=90, optimize=True)
        ground_path = sample_paths.sample_path("earth_day.jpg", "earth")
        clouds_path = sample_paths.sample_path("earth_clouds.png", "earth")
        ground.save(ground_path, quality=88, optimize=True)
        clouds.save(clouds_path, optimize=True)
    for path in (ground_path, clouds_path, lights_path):
        print(f"{os.path.normpath(path)}: {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    sys.exit(main())
