#!/usr/bin/env python3
"""Converts the Khronos Suzanne sample model into docs/samples/suzanne.obj.

    python3 tools/convert_suzanne_obj.py

Run BY HAND, not by the build: the .obj is committed, and this needs the network.

Source and licence, the reason this script exists rather than a bare download: the model comes
from KhronosGroup/glTF-Sample-Assets (Models/Suzanne), © 2017 UX3D, authored by Norbert Nopper,
released under Creative Commons Zero v1.0 Universal (CC0-1.0) — public domain, no attribution
required, though the credit is kept in the .obj header anyway. Suzanne herself is the Blender
mascot. Keeping the conversion in the repository is what makes the provenance of a borrowed
asset checkable instead of a mystery binary.

Why .obj and not the original glTF: the "3D models" example teaches that an .obj carries its
GEOMETRY ALONE, with no material, so the script's fill decides the colour — cube_tex.glb and
armillary.glb already cover the textured and the multi-material glTF paths.

Texture coordinates are dropped for the same reason (nothing samples a texture here), and
positions and normals are written with four decimals, matching knot.obj.
"""
import json
import os
import struct
import urllib.request

BASE = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/Suzanne/glTF/"

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
             5125: ("I", 4), 5126: ("f", 4)}
COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def fetch(name):
    with urllib.request.urlopen(BASE + name) as r:
        return r.read()


def accessor(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    fmt, size = COMPONENT[acc["componentType"]]
    n = COUNT[acc["type"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or size * n
    return [struct.unpack_from("<" + fmt * n, blob, base + k * stride) for k in range(acc["count"])]


def main():
    doc = json.loads(fetch("Suzanne.gltf"))
    blob = fetch("Suzanne.bin")
    prim = doc["meshes"][0]["primitives"][0]
    pos = accessor(doc, blob, prim["attributes"]["POSITION"])
    nrm = accessor(doc, blob, prim["attributes"]["NORMAL"])
    idx = [t[0] for t in accessor(doc, blob, prim["indices"])]

    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(root, "docs", "samples", "suzanne.obj")
    with open(path, "w") as f:
        f.write("# Suzanne, the Blender mascot - external model (OBJ) for Ollin\n")
        f.write("# From KhronosGroup/glTF-Sample-Assets, (c) 2017 UX3D, by Norbert Nopper.\n")
        f.write("# Creative Commons Zero v1.0 Universal. Converted by tools/convert_suzanne_obj.py\n")
        for p in pos:
            f.write("v %.4f %.4f %.4f\n" % p)
        for n in nrm:
            f.write("vn %.4f %.4f %.4f\n" % n)
        for k in range(0, len(idx), 3):
            a, b, c = (i + 1 for i in idx[k:k + 3])
            f.write(f"f {a}//{a} {b}//{b} {c}//{c}\n")
    print(f"{path}: {os.path.getsize(path)} bytes, {len(pos)} vertices, {len(idx) // 3} triangles")


if __name__ == "__main__":
    main()
