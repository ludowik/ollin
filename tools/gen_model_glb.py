#!/usr/bin/env python3
"""Generates docs/samples/armillary.glb — the COMPLEX model of the "3D models" example.

    python3 tools/gen_model_glb.py

Run BY HAND, not by the build: the .glb is committed, like the font atlases. Nothing here is read
at run time.

Why generated rather than downloaded: a third-party sample model carries a licence to honour and
to attribute, which a repository should not take on lightly. This one is ours, and its complexity
is chosen rather than inherited — five meshes, five materials, about five thousand triangles.

What it is for: cube_tex.glb already covers a glTF carrying a TEXTURE. This one covers the other
half of the loader, which nothing exercised — a model whose meshes each have their OWN material
colour (baseColorFactor). graphics.drawModel reads that colour per mesh and multiplies it by the
script's fill, so a white fill shows the model's real colours.

The node rotations are BAKED into the vertices and every node keeps an identity transform: how
raylib flattens a glTF node hierarchy is its business, and the example must not depend on it.
"""
import json
import math
import os
import struct

# ── geometry ────────────────────────────────────────────────────────────────────

def rotate(v, quat):
    """Rotates a vector by a unit quaternion (x, y, z, w)."""
    x, y, z, w = quat
    vx, vy, vz = v
    # t = 2 * (q_vec × v), then v + w*t + q_vec × t
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty),
            vy + w * ty + (z * tx - x * tz),
            vz + w * tz + (x * ty - y * tx))


def quat_axis(axis, degrees):
    ax, ay, az = axis
    n = math.sqrt(ax * ax + ay * ay + az * az) or 1.0
    a = math.radians(degrees) * 0.5
    s = math.sin(a) / n
    return (ax * s, ay * s, az * s, math.cos(a))


def torus(major, minor, nu, nv, quat=None):
    """A torus in the XZ plane, optionally rotated. Returns (positions, normals, uvs, indices)."""
    pos, nrm, uvs, idx = [], [], [], []
    for i in range(nu + 1):
        u = i / nu
        au = u * math.tau
        cu, su = math.cos(au), math.sin(au)
        for j in range(nv + 1):
            v = j / nv
            av = v * math.tau
            cv, sv = math.cos(av), math.sin(av)
            p = ((major + minor * cv) * cu, minor * sv, (major + minor * cv) * su)
            n = (cv * cu, sv, cv * su)
            if quat:
                p, n = rotate(p, quat), rotate(n, quat)
            pos.append(p)
            nrm.append(n)
            uvs.append((u, v))
    for i in range(nu):
        for j in range(nv):
            a = i * (nv + 1) + j
            b = a + nv + 1
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return pos, nrm, uvs, idx


def sphere(radius, nu, nv):
    pos, nrm, uvs, idx = [], [], [], []
    for i in range(nu + 1):
        u = i / nu
        au = u * math.tau
        for j in range(nv + 1):
            v = j / nv
            av = v * math.pi
            sv, cv = math.sin(av), math.cos(av)
            n = (sv * math.cos(au), cv, sv * math.sin(au))
            pos.append((n[0] * radius, n[1] * radius, n[2] * radius))
            nrm.append(n)
            uvs.append((u, v))
    for i in range(nu):
        for j in range(nv):
            a = i * (nv + 1) + j
            b = a + nv + 1
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return pos, nrm, uvs, idx


def cylinder(radius, height, nu, y0=0.0):
    """A closed cylinder, for the stand."""
    pos, nrm, uvs, idx = [], [], [], []
    for i in range(nu + 1):
        u = i / nu
        a = u * math.tau
        ca, sa = math.cos(a), math.sin(a)
        pos += [(radius * ca, y0, radius * sa), (radius * ca, y0 + height, radius * sa)]
        nrm += [(ca, 0.0, sa), (ca, 0.0, sa)]
        uvs += [(u, 0.0), (u, 1.0)]
    for i in range(nu):
        a = i * 2
        idx += [a, a + 1, a + 2, a + 2, a + 1, a + 3]
    # The two caps, each with its own centre vertex so the normals stay flat.
    for sign, y in ((-1.0, y0), (1.0, y0 + height)):
        centre = len(pos)
        pos.append((0.0, y, 0.0))
        nrm.append((0.0, sign, 0.0))
        uvs.append((0.5, 0.5))
        first = len(pos)
        for i in range(nu + 1):
            a = i / nu * math.tau
            pos.append((radius * math.cos(a), y, radius * math.sin(a)))
            nrm.append((0.0, sign, 0.0))
            uvs.append((0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
        for i in range(nu):
            if sign > 0:
                idx += [centre, first + i, first + i + 1]
            else:
                idx += [centre, first + i + 1, first + i]
    return pos, nrm, uvs, idx


# ── the model: an armillary sphere ─────────────────────────────────────────────
# Five parts, five materials. The rings are rotated so the three planes are distinct, which is
# what makes the object read as a sphere of rings rather than a stack.

PARTS = [
    ("equator",  torus(1.00, 0.045, 64, 12),                                   (0.78, 0.60, 0.22, 1.0)),
    ("meridian", torus(1.00, 0.045, 64, 12, quat_axis((1, 0, 0), 90)),         (0.74, 0.38, 0.24, 1.0)),
    ("colure",   torus(1.00, 0.045, 64, 12, quat_axis((0, 0, 1), 90)),         (0.60, 0.64, 0.72, 1.0)),
    ("core",     sphere(0.28, 40, 20),                                         (1.00, 0.84, 0.35, 1.0)),
    ("stand",    cylinder(0.14, 0.55, 24, y0=-1.55),                           (0.26, 0.28, 0.34, 1.0)),
]


def pack(parts):
    """Lays the geometry out in one buffer and builds the accessors and bufferViews."""
    blob = bytearray()
    views, accessors, meshes, materials = [], [], [], []

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    for name, (pos, nrm, uvs, idx), colour in parts:
        vp = view(b"".join(struct.pack("<3f", *p) for p in pos), 34962)
        vn = view(b"".join(struct.pack("<3f", *n) for n in nrm), 34962)
        vt = view(b"".join(struct.pack("<2f", *t) for t in uvs), 34962)
        vi = view(b"".join(struct.pack("<I", i) for i in idx), 34963)
        lo = [min(p[k] for p in pos) for k in range(3)]
        hi = [max(p[k] for p in pos) for k in range(3)]
        a_pos = len(accessors)
        accessors.append({"bufferView": vp, "componentType": 5126, "count": len(pos),
                          "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": vn, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        accessors.append({"bufferView": vt, "componentType": 5126, "count": len(uvs), "type": "VEC2"})
        accessors.append({"bufferView": vi, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        materials.append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": list(colour), "metallicFactor": 0.35, "roughnessFactor": 0.55}})
        meshes.append({"name": name, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_pos + 1, "TEXCOORD_0": a_pos + 2},
            "indices": a_pos + 3, "material": len(materials) - 1}]})
    return blob, views, accessors, meshes, materials


def build():
    blob, views, accessors, meshes, materials = pack(PARTS)
    doc = {
        "asset": {"version": "2.0", "generator": "ollin tools/gen_model_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(meshes)))}],
        # Identity transforms: the rotations are already baked into the vertices.
        "nodes": [{"name": m["name"], "mesh": i} for i, m in enumerate(meshes)],
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)          # the JSON chunk is padded with SPACES
    bn = bytes(blob) + b"\0" * (-len(blob) % 4)   # the BIN chunk with zeros
    total = 12 + 8 + len(js) + 8 + len(bn)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(bn), 0x004E4942) + bn
    return out


if __name__ == "__main__":
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(root, "docs", "samples", "armillary.glb")
    data = build()
    with open(path, "wb") as f:
        f.write(data)
    tris = sum(len(p[1][3]) for p in PARTS) // 3
    verts = sum(len(p[1][0]) for p in PARTS)
    print(f"{path}: {len(data)} bytes, {len(PARTS)} meshes, {verts} vertices, {tris} triangles")
