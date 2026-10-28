#!/usr/bin/env python3
"""Landscape heightmaps for the tracks: tracks/<id>.terrain (+ metadata in the JSON).

Near the circuit the ground is held at the road's height (a shelf wide enough
for verges, pit lane, grandstands). Between stretches of track at different
heights, and out to the edge, it is the smoothest surface that fits (a
Laplace solve), so hillsides run naturally from one part of the lap to the
next. Further out, rolling noise (scaled by the venue style) makes it look like
land rather than a membrane.

File: little-endian uint16 heights, row-major (z rows, x columns),
height = offset + value * scale; then one byte per vertex: how "wild" the
ground is (0 = mown grass by the track, 255 = rough land / forest floor).
Metadata goes into the track JSON "terrain". Coastal tracks get a sea: land
inside SEA polygons drops to the sea bed (the game draws water over it).

    python3 tools/terrain.py [track ...]
"""
import json
import math
import os
import sys

import numpy as np
from scipy.sparse import lil_matrix
from scipy.sparse.linalg import spsolve
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
TRACKS = os.path.join(HERE, "..", "tracks")
STYLE = {"silvermoor": "park", "brianza": "park", "ardennes": "forest", "riviera": "city",
         "styria": "park", "entrelagos": "park", "desert": "desert", "kestrel_park": "park",
         "ile_royale": "park", "marina": "city", "pannonia": "park", "gulf": "desert"}
# Rolling-hill height far from the track, and how far out it builds up.
HILLS = {"park": 7.0, "forest": 16.0, "desert": 3.0, "city": 3.0}
# Water (our coordinates): Monaco's harbour and the open sea beyond the tunnel.
SEA = {
    "riviera": {"level": -0.4, "bed": -7.0, "polys": [[
        (-205, 65), (-180, 5000), (5000, 5000), (5000, -5000), (480, -5000), (480, -480),
        (440, -150), (330, -40), (150, 30), (0, 55)]]},
}
STEP = 8.0
MARGIN = 360.0
GROUND_DROP = 0.15          # shelf a little below the verge strip, so it never pokes through


def value_noise(x, z, freq, seed):
    """Smooth 2D value noise in [-1, 1]."""
    rng = np.random.default_rng(seed)
    table = rng.uniform(-1, 1, (256, 256))
    fx, fz = x * freq, z * freq
    ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
    tx, tz = fx - ix, fz - iz
    sx, sz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)

    def t(a, b):
        return table[a % 256, b % 256]
    a = t(ix, iz) * (1 - sx) + t(ix + 1, iz) * sx
    b = t(ix, iz + 1) * (1 - sx) + t(ix + 1, iz + 1) * sx
    return a * (1 - sz) + b * sz


def build(tid):
    path = os.path.join(TRACKS, tid + ".json")
    data = json.load(open(path))
    P = np.array(data["points"], float)[:, :2]
    n = len(P)
    elev = np.array(data.get("elev", [0.0] * n), float)
    wall = float(data.get("wall_offset", 24.0))
    spacing = float(data.get("spacing", 2.0))
    style = STYLE.get(tid, "park")

    lo = P.min(0) - MARGIN
    hi = P.max(0) + MARGIN
    w = int(math.ceil((hi[0] - lo[0]) / STEP)) + 1
    h = int(math.ceil((hi[1] - lo[1]) / STEP)) + 1
    gx, gz = np.meshgrid(lo[0] + np.arange(w) * STEP, lo[1] + np.arange(h) * STEP)
    V = np.stack([gx.ravel(), gz.ravel()], 1)

    tree = cKDTree(P)
    d, idx = tree.query(V, k=48, distance_upper_bound=600.0)
    d1 = d[:, 0]
    i1 = idx[:, 0]
    # Nearest sample on a *different* stretch: far along the lap compared to
    # how close it is in space.
    d2 = np.full(len(V), np.inf)
    valid = np.isfinite(d)
    for k in range(1, d.shape[1]):
        ok = valid[:, k] & ~np.isfinite(d2)
        ik = np.where(ok, idx[:, k], 0)
        arc = np.abs(ik - i1)
        arc = np.minimum(arc, n - arc) * spacing
        other = ok & (arc > 2.5 * d[:, k] + 60.0)
        d2 = np.where(other, d[:, k], d2)

    # Shelf at road level: wall + 30 m, but never past the midpoint to
    # another stretch.
    shelf = np.minimum(wall + 30.0, np.maximum((d1 + d2) * 0.5 - 4.0, wall + 3.0))
    fixed = d1 <= shelf
    target = np.where(np.isfinite(d1), elev[np.minimum(i1, n - 1)] - GROUND_DROP, 0.0)

    # Laplace solve for the free vertices (fixed ones are boundary values).
    N = w * h
    free = np.nonzero(~fixed)[0]
    pos = -np.ones(N, int)
    pos[free] = np.arange(len(free))
    A = lil_matrix((len(free), len(free)))
    b = np.zeros(len(free))
    base = float(np.median(elev))
    for r, v in enumerate(free):
        y, x = divmod(v, w)
        nb = []
        if x > 0:
            nb.append(v - 1)
        if x < w - 1:
            nb.append(v + 1)
        if y > 0:
            nb.append(v - w)
        if y < h - 1:
            nb.append(v + w)
        # A weak pull towards the venue's median height keeps the far edge
        # from drifting.
        A[r, r] = len(nb) + 0.002
        b[r] += 0.002 * base
        for u in nb:
            if fixed[u]:
                b[r] += target[u]
            else:
                A[r, pos[u]] = -1.0
    sol = spsolve(A.tocsr(), b)
    sea = SEA.get(tid)
    H = target.copy()
    H[free] = sol
    wet = np.zeros(len(V), bool)
    if sea:
        from matplotlib.path import Path
        for poly in sea["polys"]:
            wet |= Path(poly).contains_points(V)
        wet &= ~fixed

    # Rolling land away from the circuit.
    out = np.clip((d1 - shelf) / 160.0, 0.0, 1.0)
    out = out * out * (3 - 2 * out)
    amp = HILLS[style]
    seed = sum(map(ord, tid))
    noise = (value_noise(V[:, 0], V[:, 1], 1 / 260.0, seed) * 0.65
             + value_noise(V[:, 0], V[:, 1], 1 / 90.0, seed + 1) * 0.35)
    H = H + noise * amp * out
    # Ease to the base height at the border, where the flat far plane and the
    # distant hills take over.
    ix = np.arange(w)[None, :].repeat(h, 0).ravel()
    iz = np.arange(h)[:, None].repeat(w, 1).ravel()
    e = np.minimum(np.minimum(ix, w - 1 - ix), np.minimum(iz, h - 1 - iz)) * STEP
    taper = np.clip(e / 140.0, 0.0, 1.0)
    taper = taper * taper * (3 - 2 * taper)
    H = base + (H - base) * taper
    if sea:
        # Sea bed under the water, easing up to the quays.
        near = np.clip((d1 - shelf) / 30.0, 0.0, 1.0)
        H = np.where(wet, H + (sea["bed"] - H) * near, H)
    # Mown verges by the barriers; rough land from about 10 m beyond them.
    wild = np.clip((d1 - wall - 10.0) / 35.0, 0.0, 1.0)
    wild = np.where(np.isfinite(d1), wild, 1.0)

    offset = float(H.min()) - 0.5
    scale = (float(H.max()) - offset) / 65535.0 + 1e-6
    q = np.clip(np.round((H - offset) / scale), 0, 65535).astype("<u2")
    with open(os.path.join(TRACKS, tid + ".terrain"), "wb") as f:
        f.write(q.tobytes())
        f.write(np.round(wild * 255).astype(np.uint8).tobytes())
    data["terrain"] = {"x0": round(float(lo[0]), 3), "z0": round(float(lo[1]), 3), "step": STEP,
                       "w": w, "h": h, "offset": round(offset, 4), "scale": scale, "base": round(base, 3)}
    if sea:
        data["terrain"]["sea_level"] = sea["level"]
    else:
        data["terrain"].pop("sea_level", None)
    json.dump(data, open(path, "w"), separators=(",", ":"))
    print("%-12s %4d x %-4d  heights %.1f .. %.1f m  free %d" % (tid, w, h, H.min(), H.max(), len(free)))


if __name__ == "__main__":
    for t in (sys.argv[1:] or [f[:-5] for f in sorted(os.listdir(TRACKS)) if f.endswith(".json")]):
        build(t)
