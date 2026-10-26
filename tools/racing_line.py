#!/usr/bin/env python3
"""Adds a racing line to track files: a lateral offset from the centreline
for every sample, found by minimising curvature while staying inside the
track limits (wide on entry, clip the apex, wide on exit).

Usage: python3 tools/racing_line.py tracks/*.json
"""
import json
import math
import sys

CAR_MARGIN = 1.35      # metres kept between the line and the track edge


def normals(pts):
    n = len(pts)
    out = []
    for i in range(n):
        ax, az = pts[i - 1]
        bx, bz = pts[(i + 1) % n]
        tx, tz = bx - ax, bz - az
        L = math.hypot(tx, tz) or 1.0
        tx, tz = tx / L, tz / L
        # right of travel, matching the game: tangent x UP
        out.append((-tz, tx))
    return out


def optimise(pts, half_width, iters=500):
    n = len(pts)
    nr = normals(pts)
    w = max(0.0, half_width - CAR_MARGIN)
    off = [0.0] * n
    scales = [3, 6, 12, 24]
    for it in range(iters):
        k = scales[it % len(scales)]
        line = [(pts[i][0] + nr[i][0] * off[i], pts[i][1] + nr[i][1] * off[i]) for i in range(n)]
        new = off[:]
        for i in range(n):
            # Fourth-order (biharmonic) target: fairs the line to minimise
            # curvature. A plain neighbour midpoint would instead pull it tight
            # like a string and hug every inside kerb (the shortest path).
            a2 = line[i - 2 * k]
            a1 = line[i - k]
            b1 = line[(i + k) % n]
            b2 = line[(i + 2 * k) % n]
            mx = (-a2[0] + 4 * a1[0] + 4 * b1[0] - b2[0]) / 6.0
            mz = (-a2[1] + 4 * a1[1] + 4 * b1[1] - b2[1]) / 6.0
            target = (mx - pts[i][0]) * nr[i][0] + (mz - pts[i][1]) * nr[i][1]
            v = off[i] + 0.6 * (target - off[i])
            new[i] = max(-w, min(w, v))
        off = new
    # light final smoothing so the line has no kinks where it hits the limits
    for _ in range(20):
        off = [max(-w, min(w, (off[i - 1] + 2 * off[i] + off[(i + 1) % n]) / 4)) for i in range(n)]
    return off


def curvature_radius_min(pts, off):
    n = len(pts)
    nr = normals(pts)
    line = [(pts[i][0] + nr[i][0] * off[i], pts[i][1] + nr[i][1] * off[i]) for i in range(n)]
    best = 1e9
    for i in range(n):
        a, b, c = line[i - 4], line[i], line[(i + 4) % n]
        t1 = (b[0] - a[0], b[1] - a[1])
        t2 = (c[0] - b[0], c[1] - b[1])
        ang = abs(math.atan2(t1[0] * t2[1] - t1[1] * t2[0], t1[0] * t2[0] + t1[1] * t2[1]))
        if ang > 1e-6:
            best = min(best, 8.0 / ang)     # chord midpoints are 4 samples = 8 m apart
    return best


def main():
    for path in sys.argv[1:]:
        t = json.load(open(path))
        pts = [tuple(p) for p in t["points"]]
        before = curvature_radius_min(pts, [0.0] * len(pts))
        off = optimise(pts, t["half_width"])
        after = curvature_radius_min(pts, off)
        t["line"] = [round(o, 2) for o in off]
        t["line_margin"] = CAR_MARGIN
        with open(path, "w") as f:
            json.dump(t, f, separators=(",", ":"))
        print(f"{path}: tightest radius {before:.0f} m on centreline -> {after:.0f} m on racing line")


if __name__ == "__main__":
    main()
