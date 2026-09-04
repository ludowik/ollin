#!/usr/bin/env python3
"""Generates docs/samples/model_3d/teapot.glb — the Utah teapot, tessellated from its Bezier patches.

    python3 tools/gen_teapot_glb.py

Run BY HAND, not by the build: the .glb is committed. Nothing is downloaded either — the dataset
itself lives below, which is the whole point.

What this is: Martin Newell's teapot, modelled at the University of Utah in 1975, the emblematic
test model of computer graphics. It is not a mesh but 32 bicubic Bezier patches over 290 control
points (28 in the original model, which had no bottom), and those numbers have circulated
unchanged, freely and under no copyright claim, for fifty years. They are reproduced here as
literal data rather than fetched, so the model is REBUILDABLE at any resolution and depends on no
host — which matters here, every site publishing the .bpt files being unreachable from this build
environment.

Provenance of these particular figures: the tabulation that completes the mirror-symmetric patches
omitted by Steve Baker's well-known listing, published in the README of
github.com/LUXOPHIA/UtahTeapot. They were parsed, not retyped, and checked on reading: 32 patches
of 4x4 indices, 290 points, highest index 289.

The source data is Z-up with the teapot standing along +Z; the model is turned to Y-up, centred on
its bounding box and scaled to a fixed height, so the example frames it like the others. Normals
come from the patch derivatives rather than from face averaging, which is what a parametric surface
is good for. No material is written: the geometry comes alone and the script's fill decides the
colour.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

STEPS = 12          # samples per patch side; 32 * STEPS^2 vertices, far under the u16 ceiling
HEIGHT = 2.0        # the finished model's height

# Each patch: 16 indices into POINTS, row by row, forming a 4x4 grid of control points.
PATCHES = [
    (0,0,0,0,1,2,3,4,5,5,5,5,6,7,8,9),
    (0,0,0,0,10,11,12,1,5,5,5,5,13,14,15,6),
    (0,0,0,0,4,16,17,18,5,5,5,5,9,19,20,21),
    (0,0,0,0,18,22,23,10,5,5,5,5,21,24,25,13),
    (6,7,8,9,26,27,28,29,30,31,32,33,34,35,36,37),
    (13,14,15,6,38,39,40,26,41,42,43,30,44,45,46,34),
    (9,19,20,21,29,47,48,49,33,50,51,52,37,53,54,55),
    (21,24,25,13,49,56,57,38,52,58,59,41,55,60,61,44),
    (62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77),
    (78,79,80,62,81,82,83,66,84,85,86,70,87,88,89,74),
    (65,90,91,92,69,93,94,95,73,96,97,98,77,99,100,101),
    (92,102,103,78,95,104,105,81,98,106,107,84,101,108,109,87),
    (74,75,76,77,110,111,112,113,114,115,116,117,118,119,120,121),
    (87,88,89,74,122,123,124,110,125,126,127,114,128,129,130,118),
    (77,99,100,101,113,131,132,133,117,134,135,136,121,137,138,139),
    (101,108,109,87,133,140,141,122,136,142,143,125,139,144,145,128),
    (118,119,120,121,146,147,148,149,150,151,152,153,154,155,156,157),
    (128,129,130,118,158,159,160,146,161,162,163,150,164,165,166,154),
    (121,137,138,139,149,167,168,169,153,170,171,172,157,173,174,175),
    (139,144,145,128,169,176,177,158,172,178,179,161,175,180,181,164),
    (154,155,156,157,182,183,184,185,186,187,188,189,190,190,190,190),
    (164,165,166,154,191,192,193,182,194,195,196,186,190,190,190,190),
    (157,173,174,175,185,197,198,199,189,200,201,202,190,190,190,190),
    (175,180,181,164,199,203,204,191,202,205,206,194,190,190,190,190),
    (207,208,209,210,211,212,213,214,215,216,217,218,219,220,221,222),
    (210,223,224,207,214,225,226,211,218,227,228,215,222,229,230,219),
    (219,220,221,222,231,232,233,234,235,236,237,238,239,240,241,242),
    (222,229,230,219,234,243,244,231,238,245,246,235,242,247,248,239),
    (249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264),
    (252,265,266,249,256,267,268,253,260,269,270,257,264,271,272,261),
    (261,262,263,264,273,274,275,276,277,278,279,280,281,282,283,128),
    (264,271,272,261,276,284,285,273,280,286,287,277,128,288,289,281),
]

# The 290 control points, in the source's Z-up frame.
POINTS = [
    (0, 0, 3.15), (0, -0.8, 3.15), (0.45, -0.8, 3.15), (0.8, -0.45, 3.15), (0.8, 0, 3.15), (0, 0, 2.85),
    (0, -0.2, 2.7), (0.112, -0.2, 2.7), (0.2, -0.112, 2.7), (0.2, 0, 2.7), (-0.8, 0, 3.15), (-0.8, -0.45,
    3.15), (-0.45, -0.8, 3.15), (-0.2, 0, 2.7), (-0.2, -0.112, 2.7), (-0.112, -0.2, 2.7), (0.8, 0.45,
    3.15), (0.45, 0.8, 3.15), (0, 0.8, 3.15), (0.2, 0.112, 2.7), (0.112, 0.2, 2.7), (0, 0.2, 2.7), (-0.45,
    0.8, 3.15), (-0.8, 0.45, 3.15), (-0.112, 0.2, 2.7), (-0.2, 0.112, 2.7), (0, -0.4, 2.55), (0.224, -0.4,
    2.55), (0.4, -0.224, 2.55), (0.4, 0, 2.55), (0, -1.3, 2.55), (0.728, -1.3, 2.55), (1.3, -0.728, 2.55),
    (1.3, 0, 2.55), (0, -1.3, 2.4), (0.728, -1.3, 2.4), (1.3, -0.728, 2.4), (1.3, 0, 2.4), (-0.4, 0,
    2.55), (-0.4, -0.224, 2.55), (-0.224, -0.4, 2.55), (-1.3, 0, 2.55), (-1.3, -0.728, 2.55), (-0.728,
    -1.3, 2.55), (-1.3, 0, 2.4), (-1.3, -0.728, 2.4), (-0.728, -1.3, 2.4), (0.4, 0.224, 2.55), (0.224,
    0.4, 2.55), (0, 0.4, 2.55), (1.3, 0.728, 2.55), (0.728, 1.3, 2.55), (0, 1.3, 2.55), (1.3, 0.728, 2.4),
    (0.728, 1.3, 2.4), (0, 1.3, 2.4), (-0.224, 0.4, 2.55), (-0.4, 0.224, 2.55), (-0.728, 1.3, 2.55),
    (-1.3, 0.728, 2.55), (-0.728, 1.3, 2.4), (-1.3, 0.728, 2.4), (0, -1.4, 2.4), (0.784, -1.4, 2.4), (1.4,
    -0.784, 2.4), (1.4, 0, 2.4), (0, -1.3375, 2.53125), (0.749, -1.3375, 2.53125), (1.3375, -0.749,
    2.53125), (1.3375, 0, 2.53125), (0, -1.4375, 2.53125), (0.805, -1.4375, 2.53125), (1.4375, -0.805,
    2.53125), (1.4375, 0, 2.53125), (0, -1.5, 2.4), (0.84, -1.5, 2.4), (1.5, -0.84, 2.4), (1.5, 0, 2.4),
    (-1.4, 0, 2.4), (-1.4, -0.784, 2.4), (-0.784, -1.4, 2.4), (-1.3375, 0, 2.53125), (-1.3375, -0.749,
    2.53125), (-0.749, -1.3375, 2.53125), (-1.4375, 0, 2.53125), (-1.4375, -0.805, 2.53125), (-0.805,
    -1.4375, 2.53125), (-1.5, 0, 2.4), (-1.5, -0.84, 2.4), (-0.84, -1.5, 2.4), (1.4, 0.784, 2.4), (0.784,
    1.4, 2.4), (0, 1.4, 2.4), (1.3375, 0.749, 2.53125), (0.749, 1.3375, 2.53125), (0, 1.3375, 2.53125),
    (1.4375, 0.805, 2.53125), (0.805, 1.4375, 2.53125), (0, 1.4375, 2.53125), (1.5, 0.84, 2.4), (0.84,
    1.5, 2.4), (0, 1.5, 2.4), (-0.784, 1.4, 2.4), (-1.4, 0.784, 2.4), (-0.749, 1.3375, 2.53125), (-1.3375,
    0.749, 2.53125), (-0.805, 1.4375, 2.53125), (-1.4375, 0.805, 2.53125), (-0.84, 1.5, 2.4), (-1.5, 0.84,
    2.4), (0, -1.75, 1.875), (0.98, -1.75, 1.875), (1.75, -0.98, 1.875), (1.75, 0, 1.875), (0, -2, 1.35),
    (1.12, -2, 1.35), (2, -1.12, 1.35), (2, 0, 1.35), (0, -2, 0.9), (1.12, -2, 0.9), (2, -1.12, 0.9), (2,
    0, 0.9), (-1.75, 0, 1.875), (-1.75, -0.98, 1.875), (-0.98, -1.75, 1.875), (-2, 0, 1.35), (-2, -1.12,
    1.35), (-1.12, -2, 1.35), (-2, 0, 0.9), (-2, -1.12, 0.9), (-1.12, -2, 0.9), (1.75, 0.98, 1.875),
    (0.98, 1.75, 1.875), (0, 1.75, 1.875), (2, 1.12, 1.35), (1.12, 2, 1.35), (0, 2, 1.35), (2, 1.12, 0.9),
    (1.12, 2, 0.9), (0, 2, 0.9), (-0.98, 1.75, 1.875), (-1.75, 0.98, 1.875), (-1.12, 2, 1.35), (-2, 1.12,
    1.35), (-1.12, 2, 0.9), (-2, 1.12, 0.9), (0, -2, 0.45), (1.12, -2, 0.45), (2, -1.12, 0.45), (2, 0,
    0.45), (0, -1.5, 0.225), (0.84, -1.5, 0.225), (1.5, -0.84, 0.225), (1.5, 0, 0.225), (0, -1.5, 0.15),
    (0.84, -1.5, 0.15), (1.5, -0.84, 0.15), (1.5, 0, 0.15), (-2, 0, 0.45), (-2, -1.12, 0.45), (-1.12, -2,
    0.45), (-1.5, 0, 0.225), (-1.5, -0.84, 0.225), (-0.84, -1.5, 0.225), (-1.5, 0, 0.15), (-1.5, -0.84,
    0.15), (-0.84, -1.5, 0.15), (2, 1.12, 0.45), (1.12, 2, 0.45), (0, 2, 0.45), (1.5, 0.84, 0.225), (0.84,
    1.5, 0.225), (0, 1.5, 0.225), (1.5, 0.84, 0.15), (0.84, 1.5, 0.15), (0, 1.5, 0.15), (-1.12, 2, 0.45),
    (-2, 1.12, 0.45), (-0.84, 1.5, 0.225), (-1.5, 0.84, 0.225), (-0.84, 1.5, 0.15), (-1.5, 0.84, 0.15),
    (0, -1.5, 0.075), (0.84, -1.5, 0.075), (1.5, -0.84, 0.075), (1.5, 0, 0.075), (0, -1.425, 0), (0.798,
    -1.425, 0), (1.425, -0.798, 0), (1.425, 0, 0), (0, 0, 0), (-1.5, 0, 0.075), (-1.5, -0.84, 0.075),
    (-0.84, -1.5, 0.075), (-1.425, 0, 0), (-1.425, -0.798, 0), (-0.798, -1.425, 0), (1.5, 0.84, 0.075),
    (0.84, 1.5, 0.075), (0, 1.5, 0.075), (1.425, 0.798, 0), (0.798, 1.425, 0), (0, 1.425, 0), (-0.84, 1.5,
    0.075), (-1.5, 0.84, 0.075), (-0.798, 1.425, 0), (-1.425, 0.798, 0), (2.8, 0, 2.4), (2.8, -0.15, 2.4),
    (3.2, -0.15, 2.4), (3.2, 0, 2.4), (2.9, 0, 2.475), (2.9, -0.15, 2.475), (3.45, -0.15, 2.5125), (3.45,
    0, 2.5125), (2.8, 0, 2.475), (2.8, -0.25, 2.475), (3.525, -0.25, 2.49375), (3.525, 0, 2.49375), (2.7,
    0, 2.4), (2.7, -0.25, 2.4), (3.3, -0.25, 2.4), (3.3, 0, 2.4), (3.2, 0.15, 2.4), (2.8, 0.15, 2.4),
    (3.45, 0.15, 2.5125), (2.9, 0.15, 2.475), (3.525, 0.25, 2.49375), (2.8, 0.25, 2.475), (3.3, 0.25,
    2.4), (2.7, 0.25, 2.4), (2.3, 0, 2.1), (2.3, -0.25, 2.1), (2.4, -0.25, 2.025), (2.4, 0, 2.025), (2.6,
    0, 1.425), (2.6, -0.66, 1.425), (3.1, -0.66, 0.825), (3.1, 0, 0.825), (1.7, 0, 1.425), (1.7, -0.66,
    1.425), (1.7, -0.66, 0.6), (1.7, 0, 0.6), (2.4, 0.25, 2.025), (2.3, 0.25, 2.1), (3.1, 0.66, 0.825),
    (2.6, 0.66, 1.425), (1.7, 0.66, 0.6), (1.7, 0.66, 1.425), (-1.5, 0, 2.25), (-1.5, -0.3, 2.25), (-1.6,
    -0.3, 2.025), (-1.6, 0, 2.025), (-2.5, 0, 2.25), (-2.5, -0.3, 2.25), (-2.3, -0.3, 2.025), (-2.3, 0,
    2.025), (-3, 0, 2.25), (-3, -0.3, 2.25), (-2.7, -0.3, 2.025), (-2.7, 0, 2.025), (-3, 0, 1.8), (-3,
    -0.3, 1.8), (-2.7, -0.3, 1.8), (-2.7, 0, 1.8), (-1.6, 0.3, 2.025), (-1.5, 0.3, 2.25), (-2.3, 0.3,
    2.025), (-2.5, 0.3, 2.25), (-2.7, 0.3, 2.025), (-3, 0.3, 2.25), (-2.7, 0.3, 1.8), (-3, 0.3, 1.8), (-3,
    0, 1.35), (-3, -0.3, 1.35), (-2.7, -0.3, 1.575), (-2.7, 0, 1.575), (-2.65, 0, 0.9375), (-2.65, -0.3,
    0.9375), (-2.5, -0.3, 1.125), (-2.5, 0, 1.125), (-1.9, 0, 0.6), (-1.9, -0.3, 0.6), (-2, -0.3, 0.9),
    (-2.7, 0.3, 1.575), (-3, 0.3, 1.35), (-2.5, 0.3, 1.125), (-2.65, 0.3, 0.9375), (-2, 0.3, 0.9), (-1.9,
    0.3, 0.6),
]


def bernstein(t):
    """The four cubic Bernstein weights, and their derivatives, at t."""
    u = 1.0 - t
    b = (u * u * u, 3.0 * u * u * t, 3.0 * u * t * t, t * t * t)
    d = (-3.0 * u * u, 3.0 * u * (u - 2.0 * t), 3.0 * t * (2.0 * u - t), 3.0 * t * t)
    return b, d


def evaluate(grid, u, v):
    """A point of the patch and its two tangents, by the tensor product of the Bernstein bases."""
    bu, du = bernstein(u)
    bv, dv = bernstein(v)
    p = [0.0, 0.0, 0.0]
    tu = [0.0, 0.0, 0.0]
    tv = [0.0, 0.0, 0.0]
    for i in range(4):
        for j in range(4):
            c = grid[i * 4 + j]
            for k in range(3):
                p[k] += c[k] * bu[i] * bv[j]
                tu[k] += c[k] * du[i] * bv[j]
                tv[k] += c[k] * bu[i] * dv[j]
    return p, tu, tv


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def normalise(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if n < 1e-9:
        return None
    return (v[0] / n, v[1] / n, v[2] / n)


def patch_normal(grid, u, v):
    """The surface normal, stepping away from a DEGENERATE point rather than returning a zero.

    Several patches collapse a whole row onto a single control point — the tip of the lid, the ends
    of the spout — and there one tangent vanishes, so the cross product does too. Sampling slightly
    inside the patch gives the normal the surface actually has at the limit.
    """
    for du, dv in ((0.0, 0.0), (0.001, 0.0), (0.0, 0.001), (0.001, 0.001)):
        uu = min(1.0, max(0.0, u + (du if u < 0.5 else -du)))
        vv = min(1.0, max(0.0, v + (dv if v < 0.5 else -dv)))
        _, tu, tv = evaluate(grid, uu, vv)
        n = normalise(cross(tu, tv))
        if n:
            return n
    return (0.0, 1.0, 0.0)


def build():
    pos, nrm, idx = [], [], []
    for patch in PATCHES:
        grid = [POINTS[i] for i in patch]
        base = len(pos)
        for a in range(STEPS):
            for b in range(STEPS):
                u = a / (STEPS - 1)
                v = b / (STEPS - 1)
                p, _, _ = evaluate(grid, u, v)
                n = patch_normal(grid, u, v)
                # Z-up to Y-up: (x, y, z) becomes (x, z, -y), for both point and normal.
                pos.append((p[0], p[2], -p[1]))
                nrm.append((n[0], n[2], -n[1]))
        for a in range(STEPS - 1):
            for b in range(STEPS - 1):
                q = base + a * STEPS + b
                idx += [q, q + STEPS, q + 1, q + 1, q + STEPS, q + STEPS + 1]

    lo = [min(p[k] for p in pos) for k in range(3)]
    hi = [max(p[k] for p in pos) for k in range(3)]
    scale = HEIGHT / (hi[1] - lo[1])
    mid = [(lo[k] + hi[k]) * 0.5 for k in range(3)]
    pos = [tuple((p[k] - mid[k]) * scale for k in range(3)) for p in pos]
    # The uniform scale leaves the normals unit-length; only the winding would flip on a mirror,
    # and there is none here.

    out = gl.Blob()
    v_pos = out.floats(pos, 3)
    v_nrm = out.floats(nrm, 3)
    v_idx = out.ushorts(idx)
    doc = {
        "asset": {"version": "2.0", "generator": "ollin tools/gen_teapot_glb.py",
                  "copyright": "The Utah teapot, Martin Newell, University of Utah, 1975. "
                               "Tessellated from the 32 Bezier patches of the public dataset."},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Teapot", "mesh": 0}],
        "meshes": [{"name": "Teapot", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2}]}],
        "accessors": [
            {"bufferView": v_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [min(p[k] for p in pos) for k in range(3)],
             "max": [max(p[k] for p in pos) for k in range(3)]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v_idx, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
        "bufferViews": out.views,
    }
    return gl.write_glb(doc, out.data), len(pos), len(idx) // 3


if __name__ == "__main__":
    if len(PATCHES) != 32 or len(POINTS) != 290:
        raise SystemExit(f"the dataset is not the expected one: {len(PATCHES)} patches, "
                         f"{len(POINTS)} points")
    if 32 * STEPS * STEPS > 65535:
        raise SystemExit("above 65535 vertices raylib narrows the indices to u16: lower STEPS")
    path = gl.sample_path("teapot.glb")
    data, verts, tris = build()
    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: {len(data)} bytes, {verts} vertices, {tris} triangles")
