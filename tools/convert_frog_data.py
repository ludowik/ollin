#!/usr/bin/env python3
"""Converts what the example Frog takes from the 1981 arcade game into data: docs/samples/frog/tiles.ol (the pictures) and
docs/samples/frog/arcade.ol (how the lanes are laid out).

    python3 tools/convert_frog_data.py [GFX.html Code.html]

Run BY HAND, not by the build: both files are committed, and this needs the network (unless it is given saved copies of the
two pages, in that order).

Source: Computer Archeology's analysis of the arcade game, https://computerarcheology.com/Arcade/Frogger/ — the page GFX
prints the whole graphics ROM (4096 bytes) as a hex dump and says how it is stored, and the page Code is the commented
disassembly of the program, whose data tables give the lanes. The pictures and the tables are the work of Konami (the
Sega-licensed version is the same) and they are NOT ours: they are in this repository because its owner chose to have
the original look and lanes in an example for his own use, and this script is the record of where they came from. Nothing
else in the example comes from the game's ROM, apart from what its README.md lists.

How the graphics ROM is read (all of it from the GFX page, and checked against that page's own pictures):
  - a tile is 8x8 pixels of 2 bits; one bit of each pixel comes from the first 2 KB of the ROM and the other from the
    second 2 KB (whose two data lines the page has already put right), 8 bytes per tile and per bank, the most
    significant bit being the leftmost pixel;
  - the monitor of the cabinet is turned 90 degrees clockwise, so a tile is stored on its side: every tile is turned
    here to be upright;
  - a hardware sprite is 16x16, made of FOUR consecutive tiles of the ROM (the Galaxian board's layout): 4n is the top
    left quarter, 4n+1 the top right, 4n+2 the bottom left and 4n+3 the bottom right, in the frame of the stored
    picture, which is then turned like a tile.
A picture is ONE string of digits, row after row, a digit being a colour index 0..3 (0 transparent for a sprite). What
colours the indices take is decided by the game: the colour PROM of the board is not part of the pages.

How the lanes are read (from the Code page): the program draws eleven lanes, from the top of the field to the bottom (five
of river, the median strip, five of road), each as a strip of tile pairs copied from a table — `LANE_TILES` below, the
tables at 0x1403..0x14B6, in the order of the lanes — and the number of tile pairs of a lane object, the gap after it and
how many of them there are come from one of five blocks of 33 bytes (0x2260 and the table of the five pointers), one block
per difficulty tier and one triple (stride, rows, count) per lane. The stride is a distance in bytes of the tile map, 0x20
being one tile.
"""
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sample_paths import sample_path

BASE = "https://computerarcheology.com/Arcade/Frogger/"


def fetch(name):
    with urllib.request.urlopen(BASE + name) as r:
        return r.read().decode("utf-8", errors="replace")


def plain_text(html_text):
    return re.sub(r"<[^>]+>", "\n", html_text)


def hex_lines(text, pattern):
    out = {}
    for m in re.finditer(pattern, text, flags=re.M):
        base = int(m.group(1), 16)
        for i, b in enumerate(m.group(2).split()):
            out.setdefault(base + i, int(b, 16))
    return out


def read_graphics_rom(html_text):
    rom = hex_lines(plain_text(html_text), r"^([0-9A-F]{4}): ((?:[0-9A-F]{2} ?){1,16})$")
    missing = [a for a in range(0x1000) if a not in rom]
    if missing:
        raise SystemExit("the page does not give the whole ROM: %d bytes missing, first at %04X" % (len(missing), missing[0]))
    return rom


def read_code_data(html_text):
    # The data lines of the disassembly are bare hex; a code line has its mnemonic after the bytes.
    return hex_lines(plain_text(html_text), r"^([0-9A-F]{4}): ((?:[0-9A-F]{2} ?){1,16})$")


def stored_tile(rom, n):
    rows = []
    for y in range(8):
        a = rom[n * 8 + y]
        b = rom[0x800 + n * 8 + y]
        rows.append([((a >> (7 - x)) & 1) | (((b >> (7 - x)) & 1) << 1) for x in range(8)])
    return rows


def turn_clockwise(rows):
    size = len(rows)
    return [[rows[size - 1 - x][y] for x in range(size)] for y in range(size)]


def stored_sprite(rom, s):
    quarters = [stored_tile(rom, 4 * s + k) for k in range(4)]
    return [[quarters[(y // 8) * 2 + (x // 8)][y % 8][x % 8] for x in range(16)] for y in range(16)]


def as_string(rows):
    return "".join(str(v) for row in rows for v in row)


def bytes_at(data, start, count):
    out = []
    for a in range(start, start + count):
        if a not in data:
            raise SystemExit("the Code page does not give the byte at %04X" % a)
        out.append(data[a])
    return out


# The tables of tile pairs the eleven lanes copy from, as (first address, number of bytes, number of phases); the lane in
# the middle (the median strip) has none. The addresses are those the program loads for each lane (renderFrogAnimArm0..10).
# A turtle table holds three pictures of its turtles one after the other, the same distance apart whatever a lane object
# takes of each: the table of lane 4 holds five turtles per phase (20 bytes) of which a tier uses the first three, and ends
# with four blank tiles.
LANE_SOURCES = [
    (0x1403, 16, 1),   # lane 0, river: a log
    (0x1423, 24, 3),   # lane 1, river: turtles, in their three poses of swimming
    (0x143B, 24, 1),   # lane 2, river: a long log
    (0x1453, 12, 1),   # lane 3, river: a short log
    (0x145F, 60, 3),   # lane 4, river: turtles, in their three poses of swimming
    None,              # lane 5: the median strip
    (0x149F, 8, 1),    # lane 6, road: a truck
    (0x14A7, 4, 1),    # lane 7, road: a car
    (0x14AB, 4, 1),    # lane 8, road: a car
    (0x14AF, 4, 1),    # lane 9, road: a car
    (0x14B3, 4, 1),    # lane 10, road: a car
]
TIER_POINTERS = 0x2260   # five little-endian pointers to the blocks of 33 bytes


def write_tiles(rom):
    tiles = [as_string(turn_clockwise(stored_tile(rom, n))) for n in range(256)]
    sprites = [as_string(turn_clockwise(stored_sprite(rom, s))) for s in range(64)]
    path = sample_path("tiles.ol", "frog")
    with open(path, "w") as f:
        f.write("## The pictures of the arcade game, as decoded by tools/convert_frog_data.py from the graphics ROM described at\n")
        f.write("## " + BASE + "GFX.html. Do not edit by hand.\n")
        f.write("##\n")
        f.write("## TILES: 256 pictures of 8x8, and SPRITES: 64 of 16x16, each ONE string of colour indices 0..3, row after row.\n\n")
        f.write("const TILES = [\n")
        for i, t in enumerate(tiles):
            f.write('    "%s"%s\n' % (t, "," if i < 255 else ""))
        f.write("]\n\n")
        f.write("const SPRITES = [\n")
        for i, s in enumerate(sprites):
            f.write('    "%s"%s\n' % (s, "," if i < 63 else ""))
        f.write("]\n")
    print("%s: %d bytes" % (path, os.path.getsize(path)))


def write_lanes(code):
    sources = []
    for entry in LANE_SOURCES:
        sources.append(None if entry is None else bytes_at(code, entry[0], entry[1]))
    phases = [1 if entry is None else entry[2] for entry in LANE_SOURCES]
    pointers = bytes_at(code, TIER_POINTERS, 10)
    tiers = []
    for k in range(5):
        address = pointers[2 * k] | (pointers[2 * k + 1] << 8)
        block = bytes_at(code, address, 33)
        tiers.append([block[3 * lane:3 * lane + 3] for lane in range(11)])
    path = sample_path("arcade.ol", "frog")
    with open(path, "w") as f:
        f.write("## The lanes of the arcade game, as read by tools/convert_frog_data.py from the disassembly at\n")
        f.write("## " + BASE + "Code.html. Do not edit by hand.\n")
        f.write("##\n")
        f.write("## LANE_TILES: for each of the eleven lanes (the river from the top, the median strip, the road) the tile codes of one\n")
        f.write("## object, two per row (nil for the median strip), and LANE_PHASES how many pictures of it follow each other (the three\n")
        f.write("## poses of swimming of the turtles). TIERS: for each of the five difficulty tiers and each lane, the\n")
        f.write("## three bytes [stride, rows, count] — the gap after an object (stride / 32 tiles), its length in tiles and how many\n")
        f.write("## of them the lane holds.\n\n")
        f.write("const LANE_TILES = [\n")
        for i, s in enumerate(sources):
            f.write("    %s%s\n" % ("nil" if s is None else "[" + ", ".join(str(v) for v in s) + "]", "," if i < 10 else ""))
        f.write("]\n\n")
        f.write("const LANE_PHASES = [" + ", ".join(str(n) for n in phases) + "]\n\n")
        f.write("const TIERS = [\n")
        for k, tier in enumerate(tiers):
            f.write("    [" + ", ".join("[%d, %d, %d]" % tuple(t) for t in tier) + "]%s\n" % ("," if k < 4 else ""))
        f.write("]\n")
    print("%s: %d bytes" % (path, os.path.getsize(path)))


def main():
    if len(sys.argv) > 2:
        pages = []
        for name in sys.argv[1:3]:
            with open(name, encoding="utf-8", errors="replace") as f:
                pages.append(f.read())
        gfx, code = pages
    else:
        gfx, code = fetch("GFX.html"), fetch("Code.html")
    write_tiles(read_graphics_rom(gfx))
    write_lanes(read_code_data(code))


if __name__ == "__main__":
    main()
