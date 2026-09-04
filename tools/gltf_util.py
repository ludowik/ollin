"""Shared glTF plumbing for the model converters in this directory.

Three scripts turn a borrowed asset into a sample model (Suzanne, the dragon, the helmet), and
they all need the same plumbing: finding the mesh to convert, reading a .glb container, reading an
accessor, rotating a vector, writing a .glb back. That is what lives here — nothing about any
particular model.
"""
import json
import os
import struct

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
             5125: ("I", 4), 5126: ("f", 4)}
COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


# Where the "3D models" example keeps its data. The six generators wrote these two lines each, and
# moving the models into model_3d/ therefore took six identical edits — the next move would take six
# more, with one generator liable to stay behind and write beside the catalogue.
def sample_path(name):
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    return os.path.join(root, "docs", "samples", "model_3d", name)


def rotate(v, quat):
    """Rotates a vector by a unit quaternion (x, y, z, w)."""
    x, y, z, w = quat
    vx, vy, vz = v
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty),
            vy + w * ty + (z * tx - x * tz),
            vz + w * tz + (x * ty - y * tx))


def read_glb(data):
    """Splits a .glb into its JSON document and its binary chunk."""
    if struct.unpack_from("<4s", data, 0)[0] != b"glTF":
        raise SystemExit("not a .glb file")
    doc = blob = None
    off = 12
    while off < len(data):
        length, kind = struct.unpack_from("<II", data, off)
        chunk = data[off + 8:off + 8 + length]
        if kind == JSON_CHUNK:
            doc = json.loads(chunk)
        elif kind == BIN_CHUNK:
            blob = chunk
        off += 8 + length + (-length % 4)
    return doc, blob


def accessor(doc, blob, index):
    """Reads one accessor as a list of tuples, honouring the view's byte stride."""
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    fmt, size = COMPONENT[acc["componentType"]]
    n = COUNT[acc["type"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or size * n
    return [struct.unpack_from("<" + fmt * n, blob, base + k * stride) for k in range(acc["count"])]


def mesh_node(doc, name=None):
    """The node bearing the mesh to convert — by name, or the only one there is.

    Never index the node list blindly: a source that gains a node would have the converter export
    the wrong mesh without a word, or trip over a node that carries no mesh at all.
    """
    nodes = [n for n in doc["nodes"] if "mesh" in n]
    if name is not None:
        nodes = [n for n in nodes if n.get("name") == name]
        if not nodes:
            raise SystemExit(f"no node named {name!r} carries a mesh in the source scene")
    elif len(nodes) != 1:
        raise SystemExit(f"the source scene has {len(nodes)} mesh nodes, not one: name the wanted one")
    return nodes[0]


def only_primitive(doc, node):
    """The single primitive of that node's mesh, refusing a mesh that has more than one."""
    prims = doc["meshes"][node["mesh"]]["primitives"]
    if len(prims) != 1:
        raise SystemExit(f"the source mesh now has {len(prims)} primitives, not one")
    return prims[0]


def view_bytes(doc, blob, index):
    """The raw bytes of one buffer view — for copying an embedded image across unchanged."""
    view = doc["bufferViews"][index]
    off = view.get("byteOffset", 0)
    return blob[off:off + view["byteLength"]]


class Blob:
    """Collects buffer views into one binary chunk, keeping each view 4-byte aligned."""

    def __init__(self):
        self.data = bytearray()
        self.views = []

    def view(self, payload, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        entry = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(payload)}
        if target:
            entry["target"] = target
        self.data.extend(payload)
        self.views.append(entry)
        return len(self.views) - 1

    def floats(self, rows, n, target=34962):
        return self.view(b"".join(struct.pack("<" + "f" * n, *r) for r in rows), target)

    def ushorts(self, values):
        return self.view(b"".join(struct.pack("<H", v) for v in values), 34963)


def write_glb(doc, blob):
    """Wraps a document and its binary chunk into a .glb container."""
    doc["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)                    # the JSON chunk is padded with SPACES
    bn = bytes(blob) + b"\0" * (-len(blob) % 4)    # the BIN chunk with zeros
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(bn))
    out += struct.pack("<II", len(js), JSON_CHUNK) + js
    out += struct.pack("<II", len(bn), BIN_CHUNK) + bn
    return out
