#!/usr/bin/env python3
"""Builds the two real maps of docs/samples/earth/ — the ground and a snapshot of the clouds.

    python3 tools/convert_earth_textures.py

Run BY HAND, not by the build: the images are committed, and this needs the npm registry and Pillow.

Source: the npm package `three-globe` (MIT for its code), whose example folder ships
  example/img/earth-blue-marble.jpg   the NASA "Blue Marble" composite of the Earth, 4096 x 2048,
                                      equirectangular, the northern winter's snow cover;
  example/clouds/clouds.png           a real cloud cover as an alpha mask, 4096 x 2048, which that
                                      package takes from https://github.com/turban/webgl-earth.
The package states no licence for the pictures themselves, only for its code. The Blue Marble is a
NASA image (NASA imagery is public domain unless it says otherwise); the origin of the cloud mask
is whatever turban/webgl-earth says of it, which could not be read from here (GitHub is blocked
by the proxy of the session). Check both before reusing these files anywhere else.

Why not simply ship the originals: the engine's sphere reads its texture with the LATITUDE along x
(0 at the north pole) and the LONGITUDE along y (west to east), the opposite of the usual
equirectangular layout, so both pictures are transposed here, once, instead of being turned pixel
by pixel by the script every time. The ground is reduced to 2048 x 1024 (1024 x 2048 once
transposed), the clouds to 1024 x 512.

The script also reads a few places of the SOURCE and refuses to write anything if the picture
does not show what the Earth shows there: a wrong file, a flipped map or a shifted meridian
would all fail one of those checks.
"""
import os
import subprocess
import sys
import tarfile
import tempfile

from PIL import Image

PACKAGE = "three-globe@2.45.6"
GROUND = "example/img/earth-blue-marble.jpg"
CLOUDS = "example/clouds/clouds.png"
GROUND_SIZE = (2048, 1024)
CLOUDS_SIZE = (1024, 512)


def fetch(workdir):
    subprocess.run(["npm", "pack", PACKAGE, "--silent"], cwd=workdir, check=True, capture_output=True)
    tarball = next(f for f in os.listdir(workdir) if f.endswith(".tgz"))
    with tarfile.open(os.path.join(workdir, tarball)) as tar:
        members = [m for m in tar.getmembers() if m.name in ("package/" + GROUND, "package/" + CLOUDS)]
        tar.extractall(workdir, members=members, filter="data")
    return os.path.join(workdir, "package")


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


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "docs", "samples", "earth")
    with tempfile.TemporaryDirectory() as workdir:
        package = fetch(workdir)
        ground = Image.open(os.path.join(package, GROUND)).convert("RGB")
        check_geography(ground)
        ground = ground.resize(GROUND_SIZE, Image.LANCZOS).transpose(Image.TRANSPOSE)
        clouds = Image.open(os.path.join(package, CLOUDS)).convert("RGBA")
        clouds = clouds.resize(CLOUDS_SIZE, Image.LANCZOS).transpose(Image.TRANSPOSE)
        ground_path = os.path.join(out, "earth_day.jpg")
        clouds_path = os.path.join(out, "earth_clouds.png")
        ground.save(ground_path, quality=88, optimize=True)
        clouds.save(clouds_path, optimize=True)
    for path in (ground_path, clouds_path):
        print(f"{os.path.normpath(path)}: {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    sys.exit(main())
