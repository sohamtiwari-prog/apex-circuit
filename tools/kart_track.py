#!/usr/bin/env python3
"""The kart circuits: original layouts, drawn as control points (metres,
+x east, -z north) round a closed loop in the race direction, the first
point on the start/finish straight. A centripetal Catmull-Rom spline through
them, evenly spaced at 2 m, gently smoothed; a little rise and fall; then
tracks/<id>.json in the same form as the imported circuits (run
racing_line.py and terrain.py on it after).

    python3 tools/kart_track.py [id ...]        (all of them by default)
    python3 tools/kart_track.py --plot out.png  (the layouts, for checking)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TRACKS = os.path.join(HERE, "..", "tracks")
SPACING = 2.0

# id: (name, half width, wall offset, rise and fall (m), control points)
LAYOUTS = {
    "pinecrest": ("Pinecrest Kart Circuit", 4.5, 9.0, 2.0, [
        (0, 0), (90, 0), (150, 4), (182, -22), (178, -62), (146, -80), (104, -78), (78, -102),
        (84, -138), (120, -154), (172, -150), (214, -170), (226, -214), (196, -246), (130, -252),
        (60, -246), (6, -226), (-34, -196), (-74, -186), (-108, -160), (-112, -118), (-84, -92),
        (-58, -70), (-66, -34), (-48, -6)]),
    "harbourline": ("Harbourline Karting", 4.3, 8.0, 0.6, [
        (0, 0), (120, 0), (220, 0), (260, -10), (272, -40), (255, -66), (220, -72), (170, -64), (130, -80), (90, -66), (40, -60), (10, -75), (0, -110), (20, -145), (70, -160), (150, -160), (210, -170), (250, -195), (240, -230), (190, -240), (110, -232), (30, -236), (-40, -226), (-90, -200), (-110, -150), (-100, -100), (-110, -60), (-90, -20), (-50, -2)]),
    "redrock": ("Red Rock Raceway", 4.8, 10.0, 3.5, [
        (0, 0), (150, 0), (250, -8), (310, -40), (330, -90), (310, -140), (260, -160), (210, -150), (180, -175), (190, -215), (230, -250), (220, -290), (170, -305), (100, -280), (20, -215), (-60, -150), (-95, -105), (-90, -45), (-60, -8), (-30, 0)]),
}


def catmull(pts, per_seg=40, alpha=0.5):
    """Centripetal Catmull-Rom through a closed loop of points."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]

        def tj(ti, a, b):
            return ti + math.dist(a, b) ** alpha
        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        for k in range(per_seg):
            t = t1 + (t2 - t1) * k / per_seg

            def lerp(a, b, ta, tb):
                if tb == ta:
                    return a
                return ((tb - t) / (tb - ta) * a[0] + (t - ta) / (tb - ta) * b[0],
                        (tb - t) / (tb - ta) * a[1] + (t - ta) / (tb - ta) * b[1])
            a1 = lerp(p0, p1, t0, t1)
            a2 = lerp(p1, p2, t1, t2)
            a3 = lerp(p2, p3, t2, t3)
            b1 = lerp(a1, a2, t0, t2)
            b2 = lerp(a2, a3, t1, t3)
            out.append(lerp(b1, b2, t1, t2))
    return out


def resample(pts, spacing):
    n = len(pts)
    segs = [(pts[i], pts[(i + 1) % n]) for i in range(n)]
    total = sum(math.dist(a, b) for a, b in segs)
    count = max(8, round(total / spacing))
    step = total / count
    out, seg_i, d = [], 0, 0.0
    for k in range(count):
        target = k * step
        while True:
            a, b = segs[seg_i]
            L = math.dist(a, b)
            if d + L >= target or seg_i == n - 1:
                t = 0.0 if L == 0 else (target - d) / L
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
                break
            d += L
            seg_i += 1
    return out


def smooth(pts, passes, alpha=0.5):
    n = len(pts)
    for _ in range(passes):
        pts = [(pts[i][0] + alpha * ((pts[i - 1][0] + pts[(i + 1) % n][0]) / 2 - pts[i][0]),
                pts[i][1] + alpha * ((pts[i - 1][1] + pts[(i + 1) % n][1]) / 2 - pts[i][1]))
               for i in range(n)]
    return pts


def min_radius(pts):
    n = len(pts)
    best = 1e9
    for i in range(n):
        a, b, c = pts[i - 4], pts[i], pts[(i + 4) % n]
        ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
        area = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) / 2
        if area > 1e-6:
            best = min(best, ab * bc * ca / (4 * area))
    return best


def closest_other(pts, gap_m=60.0):
    """The nearest two stretches of the lap get to each other (they need
    room for both roads, their kerbs and a barrier between)."""
    n = len(pts)
    best = 1e9
    skip = int(gap_m / SPACING)
    for i in range(0, n, 2):
        for j in range(0, n, 2):
            arc = min(abs(i - j), n - abs(i - j))
            if arc > skip:
                best = min(best, math.dist(pts[i], pts[j]))
    return best


def build(tid):
    name, half, wall, rise, ctrl = LAYOUTS[tid]
    pts = catmull(ctrl)
    pts = resample(pts, 1.0)
    pts = smooth(pts, 6)
    pts = resample(pts, SPACING)
    n = len(pts)
    length = sum(math.dist(pts[i], pts[(i + 1) % n]) for i in range(n))
    elev = [round(rise * (0.6 * math.sin(2 * math.pi * i / n) + 0.4 * math.sin(4 * math.pi * i / n + 1.1)), 2) for i in range(n)]
    out = {
        "id": tid, "name": name, "real_length_m": round(length), "length_m": round(length, 1),
        "half_width": half, "wall_offset": wall, "spacing": SPACING,
        "source": "original kart circuit layout (tools/kart_track.py)",
        "points": [[round(x, 2), round(z, 2)] for x, z in pts], "elev": elev,
        "elev_source": "gentle rise and fall (tools/kart_track.py)",
    }
    with open(os.path.join(TRACKS, tid + ".json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"{tid}: {length:.0f} m, tightest radius {min_radius(pts):.1f} m, stretches no closer than {closest_other(pts):.1f} m")
    return pts


def main():
    args = sys.argv[1:]
    if args and args[0] == "--plot":
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axs = plt.subplots(1, len(LAYOUTS), figsize=(6 * len(LAYOUTS), 6))
        for ax, tid in zip(axs, LAYOUTS):
            pts = build(tid)
            xs = [p[0] for p in pts] + [pts[0][0]]
            zs = [-p[1] for p in pts] + [-pts[0][1]]
            ax.plot(xs, zs, lw=LAYOUTS[tid][1] * 2 * 0.35, color="#333")
            ax.plot(xs[:1], zs[:1], "o", color="red")
            ax.plot(xs[:12], zs[:12], color="red")
            ax.set_aspect("equal")
            ax.set_title(LAYOUTS[tid][0])
        fig.savefig(args[1], dpi=80)
        return
    for tid in (args or LAYOUTS):
        build(tid)


if __name__ == "__main__":
    main()
