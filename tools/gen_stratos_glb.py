#!/usr/bin/env python3
"""Generates docs/samples/rally/stratos.glb — the BODY of the car in the Rally example, a Lancia Stratos.

    python3 tools/gen_stratos_glb.py

Run BY HAND, not by the build: the .glb is committed, like the font atlases. Nothing here is read at
run time and nothing is downloaded — the model is ours, so no third-party licence applies.

The body is a LOFT: a handful of cross-sections along the car's length, each a ring of 18 points, and
the skin stretched between them. The Stratos is a wedge — a low pointed nose, a windscreen raked to
the roof, a short cabin pushed forward, a high engine cover — which a few sections describe well, and
the wheel arches are notches made by lifting the underside of the sections around each axle.

The colours are PER VERTEX (the livery: white, with green and red stripes in the manner of the
Alitalia car), so the whole body is one mesh and one draw call, with no image. A colour edge can only
fall on a vertex, so every face has vertices of its own: the stripes are crisp, and the normals are
smoothed by hand instead (see corner_normal) — smooth across a curved surface, creased where the
car has an edge.

The doors are shut lines — thin dark strips set a hair proud of the flank, following it — with a handle
on each; the headlamps are four round lamps standing out of the nose, each in a black bezel.

The four WHEELS are not here: they spin and steer, so the example draws them itself. The model's
origin is at AXLE height, in the car's own frame (+Z forward, +X to the side, +Y up), the frame in
which the example draws it. WHEEL_R must therefore equal WHEEL_R in rally.ol: the ground lies at
y = -WHEEL_R.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_util as gl

WHEEL_R = 0.33      # = WHEEL_R in rally.ol

WHITE = (0.93, 0.93, 0.90)
GREEN = (0.00, 0.50, 0.22)
RED = (0.78, 0.06, 0.09)
GLASS = (0.06, 0.08, 0.11)
BLACK = (0.04, 0.04, 0.05)
SHUT_LINE = (0.10, 0.10, 0.12)
LAMP = (1.00, 0.93, 0.62)
TAIL_LAMP = (0.85, 0.05, 0.05)

# One cross-section per row: z (forward is +), underside height, half-width at the belt line (the
# widest point), belt height, top height at the centreline, how far the glasshouse is set in from
# the belt, how far the roof is set in from the glass. Heights are above the GROUND.
# Rows at hb = 0.62 sit inside a wheel arch: the underside is lifted above the tyre, which makes the
# notch the wheel shows through. The axles are at z = +1.09 and z = -1.09 (wheelbase 2.18 m).
STATIONS = [
    # z      hb    ws    hs    ht    gi    ri
    (1.82, 0.24, 0.56, 0.42, 0.48, 0.04, 0.06),    # 0  nose tip
    (1.74, 0.22, 0.74, 0.50, 0.55, 0.05, 0.06),    # 1
    (1.52, 0.22, 0.88, 0.60, 0.66, 0.05, 0.08),    # 2  front arch begins
    (1.46, 0.62, 0.90, 0.63, 0.69, 0.05, 0.08),    # 3
    (1.09, 0.62, 0.94, 0.70, 0.76, 0.05, 0.08),    # 4  front axle
    (0.72, 0.62, 0.94, 0.73, 0.79, 0.05, 0.10),    # 5
    (0.66, 0.22, 0.94, 0.74, 0.80, 0.05, 0.10),    # 6  front arch ends, foot of the windscreen
    (0.15, 0.22, 0.92, 0.76, 1.11, 0.22, 0.13),    # 7  front of the roof
    (-0.40, 0.22, 0.93, 0.78, 1.10, 0.22, 0.13),   # 8  rear of the roof
    (-0.68, 0.22, 0.95, 0.80, 0.97, 0.08, 0.08),   # 9  foot of the rear window
    (-0.74, 0.62, 0.96, 0.81, 0.98, 0.08, 0.08),   # 10 rear arch begins
    (-1.09, 0.62, 0.97, 0.82, 0.99, 0.08, 0.08),   # 11 rear axle
    (-1.44, 0.62, 0.96, 0.81, 0.97, 0.08, 0.08),   # 12
    (-1.50, 0.26, 0.94, 0.80, 0.95, 0.08, 0.08),   # 13 rear arch ends
    (-1.82, 0.34, 0.84, 0.76, 0.92, 0.08, 0.08),   # 14 tail
]

# What each strip between two sections is: the surface on top of it, and the side of it.
STRIPS = [
    ("hood", "normal"), ("hood", "normal"), ("hood", "archwall"), ("hood", "arch"),
    ("hood", "arch"), ("hood", "archwall"), ("windscreen", "normal"), ("roof", "normal"),
    ("rearglass", "normal"), ("deck", "archwall"), ("deck", "arch"), ("deck", "arch"),
    ("deck", "archwall"), ("deck", "normal"),
]

RING = 18                                   # 10 points up the right side, then 8 back down the left
RING_CREASE = {1, 4, 5, 13, 14, 17}         # the bottom edge, the belt line, the foot of the glass
STATION_CREASE = {0, 2, 3, 5, 6, 7, 8, 9, 10, 12, 13, 14}


def half_ring(st):
    """The ten points of one side of a section, from the underside's centre up to the top's centre."""
    z, hb, ws, hs, ht, gi, ri = st
    wb = ws - 0.10
    wg = ws - gi
    wr = wg - ri
    dh = ht - hs
    return [
        (0.0, hb),
        (wb, hb),
        (ws, hb + 0.14 * (hs - hb)),        # the green stripe ends here
        (ws, hb + 0.28 * (hs - hb)),        # the red one — the door starts above it
        (ws, hs),                           # the belt line
        (wg, hs + 0.30 * dh),               # the foot of the glass
        (wr, ht - 0.15 * dh),               # the edge of the roof
        (0.24, ht - 0.04 * dh),             # a stripe of the centre line, on top
        (0.12, ht - 0.01 * dh),
        (0.0, ht),
    ]


def ring(st):
    right = half_ring(st)
    pts = right + [(-x, y) for (x, y) in reversed(right[1:9])]
    return [(x, y - WHEEL_R, st[0]) for (x, y) in pts]


def half_ring_at(z):
    """The half section at any z, interpolated between the two sections that bracket it."""
    for a, b in zip(STATIONS, STATIONS[1:]):
        if b[0] <= z <= a[0]:
            t = (a[0] - z) / (a[0] - b[0])
            return half_ring(tuple(p + (q - p) * t for p, q in zip(a, b)))
    raise ValueError(f"z = {z} is outside the body")


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def unit(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (v[0] / n, v[1] / n, v[2] / n) if n > 1e-12 else (0.0, 1.0, 0.0)


class Mesh:
    def __init__(self):
        self.pos, self.nrm, self.col, self.idx = [], [], [], []

    def quad(self, pts, normals, colour):
        base = len(self.pos)
        for p, n in zip(pts, normals):
            self.pos.append(p)
            self.nrm.append(n)
            self.col.append(colour + (1.0,))
        self.idx += [base, base + 1, base + 2, base, base + 2, base + 3]

    def flat_quad(self, pts, colour, outward):
        """A flat quad, wound so that its normal points the way `outward` does."""
        n = cross(sub(pts[2], pts[0]), sub(pts[3], pts[1]))
        if sum(a * b for a, b in zip(n, outward)) < 0:
            pts = [pts[0], pts[3], pts[2], pts[1]]
            n = (-n[0], -n[1], -n[2])
        n = unit(n)
        self.quad(pts, [n] * 4, colour)

    def disc_z(self, cx, cy, z, r, colour, sign, n=24):
        """A disc in a plane of constant z, facing `sign` (+1 forward)."""
        base = len(self.pos)
        for k in range(n):
            a = 2.0 * math.pi * k / n
            self.pos.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
        self.pos.append((cx, cy, z))
        for _ in range(n + 1):
            self.nrm.append((0.0, 0.0, sign))
            self.col.append(colour + (1.0,))
        for k in range(n):
            tri = [base + k, base + (k + 1) % n, base + n]
            normal = cross(sub(self.pos[tri[1]], self.pos[tri[0]]), sub(self.pos[tri[2]], self.pos[tri[0]]))
            self.idx += tri if normal[2] * sign > 0 else [tri[0], tri[2], tri[1]]

    def cylinder_z(self, cx, cy, z0, z1, r, side, front, n=24):
        """A cylinder along Z from z0 to z1 (z1 the front end), smooth-shaded round its side."""
        for k in range(n):
            a0, a1 = 2.0 * math.pi * k / n, 2.0 * math.pi * (k + 1) / n
            n0, n1 = (math.cos(a0), math.sin(a0), 0.0), (math.cos(a1), math.sin(a1), 0.0)
            pts = [(cx + r * n0[0], cy + r * n0[1], z0), (cx + r * n1[0], cy + r * n1[1], z0),
                   (cx + r * n1[0], cy + r * n1[1], z1), (cx + r * n0[0], cy + r * n0[1], z1)]
            nrm = [n0, n1, n1, n0]
            mid = (n0[0] + n1[0], n0[1] + n1[1], 0.0)
            if sum(a * b for a, b in zip(cross(sub(pts[2], pts[0]), sub(pts[3], pts[1])), mid)) < 0:
                pts, nrm = [pts[0], pts[3], pts[2], pts[1]], [nrm[0], nrm[3], nrm[2], nrm[1]]
            self.quad(pts, nrm, side)
        self.disc_z(cx, cy, z1, r, front, 1.0, n)

    def box(self, x0, x1, y0, y1, z0, z1, colour):
        c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        corners = {(i, j, k): (x, y, z) for i, x in enumerate((x0, x1)) for j, y in enumerate((y0, y1))
                   for k, z in enumerate((z0, z1))}
        faces = [
            [(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)],
            [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], [(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)],
            [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
        ]
        for face in faces:
            pts = [corners[k] for k in face]
            centre = tuple(sum(p[a] for p in pts) / 4 for a in range(3))
            self.flat_quad(pts, colour, sub(centre, c))


def paint(top, side, k):
    """The colour of the face between ring points k and k+1 (counted on the right side)."""
    if side == "archwall":
        if k <= 3:
            return BLACK
    elif side == "arch":
        if k == 0:
            return BLACK
    else:
        if k == 0:
            return BLACK
        if k == 1:
            return GREEN
        if k == 2:
            return RED
    if k <= 4:
        return WHITE
    glazed = top in ("windscreen", "rearglass")
    if k == 5:
        return GLASS if glazed or top == "roof" else WHITE
    if k == 6:
        return GLASS if glazed else WHITE
    if glazed:
        return GLASS
    return GREEN if k == 7 else RED


SHUT_WIDTH = 0.02
SHUT_LIFT = 0.005     # how far a shut line stands proud of the flank


def shut_across(m, z, k0, k1):
    """A shut line across the flank at `z`, along the section from ring point k0 up to k1, both sides."""
    pts = half_ring_at(z)
    for sign in (-1.0, 1.0):
        for k in range(k0, k1):
            (x0, y0), (x1, y1) = pts[k], pts[k + 1]
            length = math.hypot(x1 - x0, y1 - y0)
            nx, ny = (y1 - y0) / length, -(x1 - x0) / length      # out of the body, in the section's plane
            a = (sign * (x0 + nx * SHUT_LIFT), y0 + ny * SHUT_LIFT - WHEEL_R)
            b = (sign * (x1 + nx * SHUT_LIFT), y1 + ny * SHUT_LIFT - WHEEL_R)
            h = SHUT_WIDTH / 2
            m.flat_quad([(a[0], a[1], z + h), (b[0], b[1], z + h), (b[0], b[1], z - h), (a[0], a[1], z - h)],
                        SHUT_LINE, (sign * nx, ny, 0.0))


def shut_along(m, k, z_from, z_to):
    """A shut line along the flank at ring point k, from z_from back to z_to, both sides: it follows
    the body, so it is cut at every section it crosses."""
    zs = [z_from] + [st[0] for st in STATIONS if z_to < st[0] < z_from] + [z_to]
    h = SHUT_WIDTH / 2
    for sign in (-1.0, 1.0):
        for za, zb in zip(zs, zs[1:]):
            (xa, ya), (xb, yb) = half_ring_at(za)[k], half_ring_at(zb)[k]
            m.flat_quad([(sign * (xa + SHUT_LIFT), ya - WHEEL_R - h, za), (sign * (xa + SHUT_LIFT), ya - WHEEL_R + h, za),
                         (sign * (xb + SHUT_LIFT), yb - WHEEL_R + h, zb), (sign * (xb + SHUT_LIFT), yb - WHEEL_R - h, zb)],
                        SHUT_LINE, (sign, 0.0, 0.0))


def build():
    rings = [ring(st) for st in STATIONS]
    nst = len(rings)
    nstrips = nst - 1

    # Which way is out: the flank face of a hood strip must face +X. One test orients every face,
    # since the whole skin is wound the same way.
    a, b, c, d = rings[1][3], rings[1][4], rings[2][4], rings[2][3]
    flip = cross(sub(c, a), sub(d, b))[0] < 0

    def corners(s, g):
        g1 = (g + 1) % RING
        quad = [rings[s][g], rings[s][g1], rings[s + 1][g1], rings[s + 1][g]]
        return [quad[0], quad[3], quad[2], quad[1]] if flip else quad

    faces = [[cross(sub(q[2], q[0]), sub(q[3], q[1])) for q in (corners(s, g) for g in range(RING))]
             for s in range(nstrips)]

    def corner_normal(s, g, i, dj):
        """The normal of the corner of face (s, g) at section i, ring offset dj: the sum of the faces
        around that vertex, minus those across a crease."""
        other_s = s - 1 if i == s else s + 1
        smooth_s = i not in STATION_CREASE and 0 <= other_s < nstrips
        other_g = (g - 1) % RING if dj == 0 else (g + 1) % RING
        smooth_g = (g + dj) % RING not in RING_CREASE
        n = faces[s][g]
        if smooth_s:
            n = add(n, faces[other_s][g])
        if smooth_g:
            n = add(n, faces[s][other_g])
        if smooth_s and smooth_g:
            n = add(n, faces[other_s][other_g])
        return unit(n)

    m = Mesh()
    for s in range(nstrips):
        top, side = STRIPS[s]
        for g in range(RING):
            k = g if g <= 8 else RING - 1 - g
            q = corners(s, g)
            # corners() reorders them when flipped; recover each corner's (section, ring offset)
            order = [(s, 0), (s + 1, 0), (s + 1, 1), (s, 1)] if flip else [(s, 0), (s, 1), (s + 1, 1), (s + 1, 0)]
            nrm = [corner_normal(s, g, i, dj) for (i, dj) in order]
            m.quad(q, nrm, paint(top, side, k))

    # The two ends: a black grille and a black tail panel. The headlamps stand out of the first, the
    # tail lamps lie flat on the second.
    for idx, sign in ((0, 1.0), (nst - 1, -1.0)):
        r = rings[idx]
        centre = tuple(sum(p[a] for p in r) / RING for a in range(3))
        base = len(m.pos)
        for p in r + [centre]:
            m.pos.append(p)
            m.nrm.append((0.0, 0.0, sign))
            m.col.append(BLACK + (1.0,))
        for g in range(RING):
            a, b = g, (g + 1) % RING
            tri = [base + a, base + b, base + RING]
            normal = cross(sub(m.pos[tri[1]], m.pos[tri[0]]), sub(m.pos[tri[2]], m.pos[tri[0]]))
            m.idx += tri if normal[2] * sign > 0 else [tri[0], tri[2], tri[1]]
    # Four round headlamps standing out of the nose: two large ones inside, two smaller outside, each
    # in a black bezel a little wider than the glass.
    nose = STATIONS[0]
    lamp_y = (nose[1] + nose[4]) / 2 - WHEEL_R
    for sign in (-1.0, 1.0):
        for x, r in ((0.17, 0.085), (0.40, 0.07)):
            m.cylinder_z(sign * x, lamp_y, nose[0], nose[0] + 0.025, r * 1.20, BLACK, BLACK)
            m.cylinder_z(sign * x, lamp_y, nose[0], nose[0] + 0.045, r, BLACK, LAMP)

    tail_z = STATIONS[-1][0] - 0.004
    for x in (-0.34, 0.34):
        y1 = STATIONS[-1][1] - WHEEL_R + 0.10
        m.flat_quad([(x - 0.18, y1, tail_z), (x + 0.18, y1, tail_z), (x + 0.18, y1 + 0.10, tail_z),
                     (x - 0.18, y1 + 0.10, tail_z)], TAIL_LAMP, (0, 0, -1))

    # The doors: a shut line up the front edge and another up the back edge, from the top of the sill
    # stripes to the foot of the glass, joined by one along the bottom, and a handle at the rear.
    door_front, door_rear = 0.50, -0.55
    for z in (door_front, door_rear):
        shut_across(m, z, 3, 5)
    shut_along(m, 3, door_front, door_rear)
    for sign in (-1.0, 1.0):
        ws, hs = half_ring_at(-0.44)[4]
        x0, x1 = sorted((sign * (ws - 0.01), sign * (ws + 0.035)))
        m.box(x0, x1, hs - WHEEL_R - 0.12, hs - WHEEL_R - 0.08, -0.50, -0.38, BLACK)

    # The wing on the tail, with its end plates, and a mirror on each side.
    top = STATIONS[-1][4] - WHEEL_R
    m.box(-0.88, 0.88, top + 0.10, top + 0.14, -2.04, -1.74, BLACK)
    for x0, x1 in ((-0.91, -0.88), (0.88, 0.91)):
        m.box(x0, x1, top - 0.02, top + 0.20, -2.04, -1.74, WHITE)
    belt = STATIONS[6][3] - WHEEL_R
    edge = STATIONS[6][2]
    for sign in (-1.0, 1.0):
        x0, x1 = sorted((sign * (edge - 0.12), sign * (edge + 0.10)))
        m.box(x0, x1, belt + 0.02, belt + 0.11, 0.50, 0.58, BLACK)

    return m


def to_glb(m):
    return gl.write_colored_mesh_glb("Stratos", "ollin tools/gen_stratos_glb.py", m.pos, m.nrm, m.col, m.idx)


if __name__ == "__main__":
    mesh = build()
    if len(mesh.pos) > 65535:
        raise SystemExit("above 65535 vertices raylib narrows the indices to u16")
    data = to_glb(mesh)
    path = gl.sample_path("stratos.glb", "rally")
    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: {len(data)} bytes, {len(mesh.pos)} vertices, {len(mesh.idx) // 3} triangles")
