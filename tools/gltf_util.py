"""Shared glTF plumbing for the model converters in this directory.

Three scripts turn a borrowed asset into a sample model (Suzanne, the dragon, the helmet), and
they all need the same four things: reading a .glb container, reading an accessor, rotating a
vector, writing a .glb back. That is what lives here — nothing about any particular model.
"""
import json
import struct

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
             5125: ("I", 4), 5126: ("f", 4)}
COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


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
