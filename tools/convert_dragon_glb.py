#!/usr/bin/env python3
"""Converts the Stanford dragon into docs/samples/model_3d/dragon.glb.

    python3 tools/convert_dragon_glb.py

Run BY HAND, not by the build: the .glb is committed, and this needs the network.

Source and licence, the reason this script exists rather than a bare download: the mesh comes from
KhronosGroup/glTF-Sample-Assets (Models/DragonAttenuation), itself a decimation of the dragon
scanned by the **Stanford Computer Graphics Laboratory**, whose terms REQUIRE that credit and
allow free redistribution but NOT commercial use without permission. That restriction is carried
by this one file, and it is why the credit is written into the model's own metadata.

Why it is here: mass. The dragon is 91 216 triangles of scanned geometry, an order of magnitude
above every other sample model, so it measures what the loader and one draw call really cost.

What is kept: the dragon mesh ALONE. The source scene also holds a cloth backdrop and glass
material extensions (transmission, volume) that Ollin's shader knows nothing about. Texture
coordinates are dropped (nothing samples a texture) and no material is written, so the model
carries its geometry only and the script's fill decides the colour — the same lesson as
suzanne.obj. The node's transform is BAKED into the vertices and the normals, so how raylib
flattens a node hierarchy cannot change the result.

Output is a .glb and not an .obj: the same geometry as OBJ text is roughly 6 MB, against 2.9 MB
of packed floats here.
"""
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

URL = ("https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/"
       "Models/DragonAttenuation/glTF-Binary/DragonAttenuation.glb")
MESH_NAME = "Dragon"

MAX_VERTS = 65535   # raylib stores mesh indices as unsigned short (see the split below)


def split(pos, nrm, idx):
    """Cuts the geometry into parts of at most MAX_VERTS vertices, each with its own indices.

    Not an optimisation: raylib's Mesh keeps indices as unsigned short, so it CONVERTS a u32 index
    buffer down to u16 with a warning, and a mesh of 76 809 vertices comes out as a spray of
    triangles pointing anywhere (seen). One primitive per part is the fix; raylib then makes one
    mesh per part, so the cost is one extra draw call.
    """
    parts = []
    remap, out_pos, out_nrm, out_idx = {}, [], [], []
    for k in range(0, len(idx), 3):
        tri = idx[k:k + 3]
        fresh = sum(1 for v in tri if v not in remap)
        if len(out_pos) + fresh > MAX_VERTS:
            parts.append((out_pos, out_nrm, out_idx))
            remap, out_pos, out_nrm, out_idx = {}, [], [], []
        for v in tri:
            if v not in remap:
                remap[v] = len(out_pos)
                out_pos.append(pos[v])
                out_nrm.append(nrm[v])
            out_idx.append(remap[v])
    parts.append((out_pos, out_nrm, out_idx))
    return parts


def build(parts):
    """Packs the geometry-only parts into a .glb, with the Stanford credit in the asset metadata."""
    out = gl.Blob()
    accessors, primitives = [], []
    for pos, nrm, idx in parts:
        v_pos = out.floats(pos, 3)
        v_nrm = out.floats(nrm, 3)
        v_idx = out.ushorts(idx)
        base = len(accessors)
        accessors += [
            {"bufferView": v_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [min(p[k] for p in pos) for k in range(3)],
             "max": [max(p[k] for p in pos) for k in range(3)]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v_idx, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ]
        primitives.append({"attributes": {"POSITION": base, "NORMAL": base + 1}, "indices": base + 2})
    doc = {
        "asset": {
            "version": "2.0",
            "generator": "ollin tools/convert_dragon_glb.py",
            "copyright": "Stanford dragon - credit: Stanford Computer Graphics Laboratory. "
                         "Free redistribution allowed, no commercial use without permission. "
                         "Decimated mesh from KhronosGroup/glTF-Sample-Assets.",
        },
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Dragon", "mesh": 0}],
        "meshes": [{"name": "Dragon", "primitives": primitives}],
        "accessors": accessors,
        "bufferViews": out.views,
    }
    return gl.write_glb(doc, out.data)


def main():
    with urllib.request.urlopen(URL) as r:
        doc, blob = gl.read_glb(r.read())

    node = gl.mesh_node(doc, MESH_NAME)
    prim = gl.only_primitive(doc, node)
    pos = gl.accessor(doc, blob, prim["attributes"]["POSITION"])
    nrm = gl.accessor(doc, blob, prim["attributes"]["NORMAL"])
    idx = [t[0] for t in gl.accessor(doc, blob, prim["indices"])]

    # Bake the node transform: the source dragon lies on its back under a quarter turn about X.
    # The rotation applies to the normals as well; the UNIFORM scale does not, which is why a
    # non-uniform one is refused rather than silently skewing them.
    sx, sy, sz = node.get("scale", [1.0, 1.0, 1.0])
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    quat = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    if "matrix" in node or not sx == sy == sz:
        raise SystemExit("the source node now carries a matrix or a non-uniform scale: "
                         "the normals would need the inverse-transpose")
    pos = [tuple(c * sx + t for c, t in zip(gl.rotate(p, quat), (tx, ty, tz))) for p in pos]
    nrm = [gl.rotate(n, quat) for n in nrm]

    path = gl.sample_path("dragon.glb")
    parts = split(pos, nrm, idx)
    data = build(parts)
    with open(path, "wb") as f:
        f.write(data)
    verts = sum(len(p[0]) for p in parts)
    tris = sum(len(p[2]) for p in parts) // 3
    print(f"{path}: {len(data)} bytes, {len(parts)} parts, {verts} vertices, {tris} triangles")


if __name__ == "__main__":
    main()
