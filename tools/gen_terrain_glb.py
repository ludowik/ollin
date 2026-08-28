#!/usr/bin/env python3
"""Generates docs/samples/terrain.glb — the PER-VERTEX COLOUR model of the "3D models" example.

    python3 tools/gen_terrain_glb.py

Run BY HAND, not by the build: the .glb is committed, like the font atlases. Nothing here is read
at run time, and nothing is downloaded — the model is ours, so no third-party licence applies.

What it is for: the third way a file can carry its appearance, the one no other sample shows.
A borrowed model would not do: almost none carry COLOR_0, and the point is precisely that a single
mesh holds MANY colours with no texture and no extra draw call. Here the colour comes from the
altitude — water, sand, grass, rock, snow — so the relief reads without a single image file.

The height field is a sum of sine waves rather than noise: it is reproducible without a noise
implementation to agree on, and the exact shape does not matter.
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

SIDE = 120          # vertices per side; 119 * 119 * 2 triangles
EXTENT = 2.0        # the terrain spans [-EXTENT, +EXTENT] on X and Z
HEIGHT = 0.55

# Colour by altitude, in metres of the model: (ceiling, r, g, b). Read in order, first match wins.
BANDS = [
    (-0.18, 0.16, 0.29, 0.52),   # deep water
    (-0.06, 0.24, 0.45, 0.66),   # shallow water
    (0.00, 0.80, 0.74, 0.50),    # sand
    (0.16, 0.36, 0.55, 0.28),    # grass
    (0.34, 0.28, 0.42, 0.24),    # forest
    (0.50, 0.45, 0.42, 0.38),    # rock
    (99.0, 0.92, 0.92, 0.94),    # snow
]


def height(x, z):
    return HEIGHT * (0.6 * math.sin(x * 1.7) * math.cos(z * 1.3)
                     + 0.3 * math.sin(x * 3.1 + 1.2) * math.sin(z * 2.7)
                     + 0.1 * math.cos(x * 6.3) * math.cos(z * 5.9))


def colour(y):
    for ceiling, r, g, b in BANDS:
        if y <= ceiling:
            return (r, g, b, 1.0)
    return BANDS[-1][1:] + (1.0,)


def build():
    pos, col = [], []
    step = 2.0 * EXTENT / (SIDE - 1)
    for j in range(SIDE):
        for i in range(SIDE):
            x = -EXTENT + i * step
            z = -EXTENT + j * step
            y = height(x, z)
            pos.append((x, y, z))
            col.append(colour(y))

    # Normals from the analytic slope: a central difference on the height field, which is exact
    # enough here and spares accumulating face normals per vertex.
    nrm = []
    d = step * 0.5
    for j in range(SIDE):
        for i in range(SIDE):
            x = -EXTENT + i * step
            z = -EXTENT + j * step
            dx = (height(x + d, z) - height(x - d, z)) / (2.0 * d)
            dz = (height(x, z + d) - height(x, z - d)) / (2.0 * d)
            n = (-dx, 1.0, -dz)
            length = math.sqrt(n[0] * n[0] + 1.0 + n[2] * n[2])
            nrm.append((n[0] / length, n[1] / length, n[2] / length))

    idx = []
    for j in range(SIDE - 1):
        for i in range(SIDE - 1):
            a = j * SIDE + i
            b = a + SIDE
            idx += [a, b, a + 1, a + 1, b, b + 1]

    out = gl.Blob()
    v_pos = out.floats(pos, 3)
    v_nrm = out.floats(nrm, 3)
    # COLOR_0 as four unsigned bytes per vertex, normalised: what raylib expects in mesh.colors,
    # and four times smaller than floats.
    v_col = out.view(b"".join(struct.pack("<4B", *(int(round(c * 255.0)) for c in rgba))
                              for rgba in col), 34962)
    v_idx = out.ushorts(idx)
    doc = {
        "asset": {"version": "2.0", "generator": "ollin tools/gen_terrain_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Terrain", "mesh": 0}],
        "meshes": [{"name": "Terrain", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3}]}],
        "accessors": [
            {"bufferView": v_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [min(p[k] for p in pos) for k in range(3)],
             "max": [max(p[k] for p in pos) for k in range(3)]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v_col, "componentType": 5121, "count": len(col), "type": "VEC4",
             "normalized": True},
            {"bufferView": v_idx, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
        "bufferViews": out.views,
    }
    return gl.write_glb(doc, out.data), len(pos), len(idx) // 3


if __name__ == "__main__":
    if SIDE * SIDE > 65535:
        raise SystemExit("above 65535 vertices raylib narrows the indices to u16: lower SIDE")
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(root, "docs", "samples", "terrain.glb")
    data, verts, tris = build()
    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: {len(data)} bytes, {verts} vertices, {tris} triangles")
