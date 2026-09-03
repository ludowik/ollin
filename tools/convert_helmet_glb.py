#!/usr/bin/env python3
"""Converts the Damaged Helmet into docs/samples/model_3d/helmet.glb.

    python3 tools/convert_helmet_glb.py

Run BY HAND, not by the build: the .glb is committed, and this needs the network.

Source and licence: KhronosGroup/glTF-Sample-Assets (Models/DamagedHelmet). © 2018 ctxwing for
the rebuild and glTF conversion, under CC-BY 4.0; © 2016 theblueturtle_ for the earlier version
of the model, under CC-BY-NC 4.0. Credit is REQUIRED and the non-commercial clause applies, like
the dragon. Both credits are written into the model's own metadata.

Why it is here: it is the model every PBR renderer has shown since 2016, and it is the only sample
carrying a real painted TEXTURE over sculpted geometry — rubik.glb only proves the path exists.

What is kept: geometry, the base colour texture, and nothing else. The source also carries
metallic-roughness, emissive, occlusion and normal maps, which Ollin's shader never samples;
shipping them would be 2.7 MB the engine cannot read. The node's quarter turn about X is baked
into the vertices and the normals, so how raylib flattens a node hierarchy cannot change the
result.
"""
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

URL = ("https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/"
       "Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb")

CREDIT = ("Damaged Helmet - (c) 2018 ctxwing (rebuild and glTF conversion, CC-BY 4.0), "
          "(c) 2016 theblueturtle_ (earlier version of the model, CC-BY-NC 4.0). "
          "Credit required, no commercial use. From KhronosGroup/glTF-Sample-Assets.")


def main():
    with urllib.request.urlopen(URL) as r:
        doc, blob = gl.read_glb(r.read())

    node = gl.mesh_node(doc)
    prim = gl.only_primitive(doc, node)
    pos = gl.accessor(doc, blob, prim["attributes"]["POSITION"])
    nrm = gl.accessor(doc, blob, prim["attributes"]["NORMAL"])
    uvs = gl.accessor(doc, blob, prim["attributes"]["TEXCOORD_0"])
    idx = [t[0] for t in gl.accessor(doc, blob, prim["indices"])]
    if len(pos) > 65535:
        raise SystemExit("above 65535 vertices, raylib narrows the indices to u16: split needed")

    quat = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    if "matrix" in node or "scale" in node or "translation" in node:
        raise SystemExit("the source node now carries a scale, a translation or a matrix")
    pos = [gl.rotate(p, quat) for p in pos]
    nrm = [gl.rotate(n, quat) for n in nrm]

    source_image = doc["images"][doc["materials"][0]["pbrMetallicRoughness"]
                                ["baseColorTexture"]["index"]]
    texture = gl.view_bytes(doc, blob, source_image["bufferView"])

    out = gl.Blob()
    v_pos = out.floats(pos, 3)
    v_nrm = out.floats(nrm, 3)
    v_uvs = out.floats(uvs, 2)
    v_idx = out.ushorts(idx)
    v_img = out.view(texture)
    built = {
        "asset": {"version": "2.0", "generator": "ollin tools/convert_helmet_glb.py",
                  "copyright": CREDIT},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "DamagedHelmet", "mesh": 0}],
        "meshes": [{"name": "DamagedHelmet", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": 3, "material": 0}]}],
        "materials": [{"name": "helmet", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "textures": [{"source": 0}],
        "images": [{"mimeType": source_image["mimeType"], "bufferView": v_img}],
        "accessors": [
            {"bufferView": v_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": [min(p[k] for p in pos) for k in range(3)],
             "max": [max(p[k] for p in pos) for k in range(3)]},
            {"bufferView": v_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": v_uvs, "componentType": 5126, "count": len(uvs), "type": "VEC2"},
            {"bufferView": v_idx, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
        "bufferViews": out.views,
    }

    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    path = os.path.join(root, "docs", "samples", "model_3d", "helmet.glb")
    data = gl.write_glb(built, out.data)
    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: {len(data)} bytes, {len(pos)} vertices, {len(idx) // 3} triangles, "
          f"texture {len(texture)} bytes")


if __name__ == "__main__":
    main()
