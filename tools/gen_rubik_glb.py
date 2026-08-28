#!/usr/bin/env python3
"""Generates docs/samples/rubik.glb — the TEXTURED model of the "3D models" example.

    python3 tools/gen_rubik_glb.py

Run BY HAND, not by the build: the .glb is committed, like the font atlases. Nothing is downloaded
— the model is ours, so no third-party licence applies. (The Rubik's Cube name is a trademark of
Spin Master; what is drawn here is a 3x3 sticker pattern, not a brand, and nothing carries a mark.)

What it is for: a glTF that carries its own TEXTURE. It replaces a cube wrapped in a repeating 4x4
checker, which showed the same picture on all six faces — the least a texture can prove. A solved
3x3 cube needs an ATLAS instead: the six faces share one image, each reading its OWN cell, which is
what a real textured model does and what the loader must get right.

The 26 cubies are REAL geometry, separated by a gap, and not a grid painted on one box: the edges of
every small cube then show, on the silhouette as well as inside, and the light catches them. Each
outer face reads its own sticker from the atlas — the mapping is a function of the vertex position,
so the painting lines up with the geometry by construction rather than by a table to keep in step.
The centre cubie is left out: it can never be seen.

The cube is SCRAMBLED: each of the 54 stickers gets its own colour, nine of each. It is a shuffle
of the stickers with a fixed seed, so the file is reproducible — NOT the result of legal turns, so
the state is very probably unsolvable. Nothing here claims otherwise; what matters is that the six
faces no longer show one flat colour each, which is what a texture atlas is for.

The picture is drawn here pixel by pixel and written as a PNG by write_png below, so the file has
no dependency and the pattern is editable by changing the table of colours.
"""
import os
import random
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

# The three must satisfy 3 * STICKER + 4 * GAP == CELL, checked below: the first version had
# 3 * 9 + 4 * 1 = 31 for a cell of 32, so the leftover pixel widened the last border and the
# stickers sat off-centre on their face.
CELL = 68          # pixels per face in the atlas
STICKER = 20       # pixels per sticker
GAP = 2            # the same width between two stickers and around the grid

# The six faces of a solved cube, in the order the UVs below use them: right, left, top, bottom,
# front, back. The classic colour scheme, opposite faces paired.
FACES = [
    ("right", (0xB7, 0x1C, 0x1C)),
    ("left", (0xE8, 0x71, 0x0A)),
    ("top", (0xF2, 0xF2, 0xF2)),
    ("bottom", (0xF5, 0xD1, 0x1E)),
    ("front", (0x1B, 0x5E, 0xC4)),
    ("back", (0x1F, 0x8A, 0x3C)),
]
PLASTIC = (0x14, 0x14, 0x16)   # the body between the stickers

ATLAS_COLS = 3
ATLAS_ROWS = 2

SCRAMBLE_SEED = 20260828       # a fixed seed: the same file comes out of every run


def scramble():
    """The colour of each sticker: [face][row][column], nine of each colour, shuffled."""
    deck = [colour for _, colour in FACES for _ in range(9)]
    random.Random(SCRAMBLE_SEED).shuffle(deck)
    return [[[deck[f * 9 + sy * 3 + sx] for sx in range(3)] for sy in range(3)]
            for f in range(len(FACES))]


def write_png(width, height, rows):
    """A minimal 8-bit RGB PNG. Writing it here avoids a dependency for a 204x136 image."""
    raw = b"".join(b"\0" + bytes(px for pixel in row for px in pixel) for row in rows)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def atlas():
    """The six faces side by side: 3 columns, 2 rows, each cell a 3x3 sticker grid."""
    w, h = ATLAS_COLS * CELL, ATLAS_ROWS * CELL
    rows = [[PLASTIC] * w for _ in range(h)]
    stickers = scramble()
    for index in range(len(FACES)):
        ox = (index % ATLAS_COLS) * CELL
        oy = (index // ATLAS_COLS) * CELL
        for sy in range(3):
            for sx in range(3):
                colour = stickers[index][sy][sx]
                x0 = ox + GAP + sx * (STICKER + GAP)
                y0 = oy + GAP + sy * (STICKER + GAP)
                for y in range(y0, y0 + STICKER):
                    for x in range(x0, x0 + STICKER):
                        rows[y][x] = colour
    return w, h, rows


# One quad per face: the four corners counter-clockwise seen from outside, and the face normal.
QUADS = [
    ([(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)], (1, 0, 0)),    # right
    ([(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)], (-1, 0, 0)),  # left
    ([(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)], (0, 1, 0)),    # top
    ([(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)], (0, -1, 0)),  # bottom
    ([(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)], (0, 0, 1)),    # front
    ([(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)], (0, 0, -1)),  # back
]


GAP3D = 0.05       # the space between two cubies, in the cube's units (the cube spans -1..1)


def face_uv(face, point):
    """Where a point of a face lands in the atlas, from its POSITION on that face.

    The face's own axes come from its quad: corner0 to corner1 is u, corner0 to corner3 is v. A
    point is therefore mapped without any per-cubie table, and the painted stickers line up with the
    geometry on their own. The half-pixel inset keeps the outermost cubies from sampling the
    neighbouring cell.
    """
    corners, _ = QUADS[face]
    origin = corners[0]
    du = [b - a for a, b in zip(origin, corners[1])]
    dv = [b - a for a, b in zip(origin, corners[3])]
    rel = [p - o for p, o in zip(point, origin)]
    u = sum(r * d for r, d in zip(rel, du)) / sum(d * d for d in du)
    v = sum(r * d for r, d in zip(rel, dv)) / sum(d * d for d in dv)
    cx = (face % ATLAS_COLS) * CELL
    cy = (face // ATLAS_COLS) * CELL
    w, h = ATLAS_COLS * CELL, ATLAS_ROWS * CELL
    inset = 0.5 / CELL
    u = min(1.0 - inset, max(inset, u))
    v = min(1.0 - inset, max(inset, v))
    return (cx + u * CELL) / w, (cy + v * CELL) / h


def plastic_uv():
    """A texel of the black body, for the faces that look inwards: the border of the first cell."""
    w, h = ATLAS_COLS * CELL, ATLAS_ROWS * CELL
    return (0.5 / w, 0.5 / h)


def build():
    pos, nrm, uvs, idx = [], [], [], []
    pitch = 2.0 / 3.0
    half = (pitch - GAP3D) / 2.0
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            for k in (-1, 0, 1):
                if i == 0 and j == 0 and k == 0:
                    continue                      # the middle cubie is invisible
                centre = (i * pitch, j * pitch, k * pitch)
                for face, (corners, normal) in enumerate(QUADS):
                    # A face is a STICKER when the cubie sits at the end of the axis it looks along;
                    # otherwise it faces a neighbour and stays black.
                    axis = 0 if normal[0] else (1 if normal[1] else 2)
                    outward = (i, j, k)[axis] == (1 if sum(normal) > 0 else -1)
                    base = len(pos)
                    for corner in corners:
                        point = tuple(c + x * half for c, x in zip(centre, corner))
                        pos.append(point)
                        nrm.append(normal)
                        uvs.append(face_uv(face, point) if outward else plastic_uv())
                    idx += [base, base + 1, base + 2, base, base + 2, base + 3]

    width, height, rows = atlas()
    out = gl.Blob()
    v_pos = out.floats(pos, 3)
    v_nrm = out.floats(nrm, 3)
    v_uvs = out.floats(uvs, 2)
    v_idx = out.ushorts(idx)
    v_img = out.view(write_png(width, height, rows))
    doc = {
        "asset": {"version": "2.0", "generator": "ollin tools/gen_rubik_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Cube", "mesh": 0}],
        "meshes": [{"name": "Cube", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": 3, "material": 0}]}],
        "materials": [{"name": "stickers", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
        "textures": [{"sampler": 0, "source": 0}],
        # NEAREST: the stickers are flat colours and must stay crisp, whatever the zoom.
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"mimeType": "image/png", "bufferView": v_img}],
        "accessors": [
            {"bufferView": v_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [min(p[c] for p in pos) for c in range(3)],
             "max": [max(p[c] for p in pos) for c in range(3)]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v_uvs, "componentType": 5126, "count": len(uvs), "type": "VEC2"},
            {"bufferView": v_idx, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
        "bufferViews": out.views,
    }
    return gl.write_glb(doc, out.data), len(pos), len(idx) // 3


def check_layout():
    """The sticker grid must fill its cell exactly, and each quad must wind counter-clockwise SEEN
    FROM OUTSIDE, or the face is back-facing.

    Written as a check rather than trusted: the first version had the two side quads reversed, and
    a culled face is not an error anywhere — the cube simply came out open on that side, which was
    only caught by looking at a render.
    """
    if 3 * STICKER + 4 * GAP != CELL:
        raise SystemExit(f"3 * {STICKER} + 4 * {GAP} != {CELL}: the borders would come out uneven")
    for corners, normal in QUADS:
        e1 = [b - a for a, b in zip(corners[0], corners[1])]
        e2 = [b - a for a, b in zip(corners[0], corners[2])]
        facing = (e1[1] * e2[2] - e1[2] * e2[1],
                  e1[2] * e2[0] - e1[0] * e2[2],
                  e1[0] * e2[1] - e1[1] * e2[0])
        if sum(f * n for f, n in zip(facing, normal)) <= 0:
            raise SystemExit(f"the quad of normal {normal} winds the wrong way: it would be culled")


if __name__ == "__main__":
    check_layout()
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(root, "docs", "samples", "rubik.glb")
    data, verts, tris = build()
    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: {len(data)} bytes, {verts} vertices, {tris} triangles")
