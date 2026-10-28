#!/usr/bin/env python3
"""Convert a real circuit outline (GeoJSON LineString, lon/lat) into a game
track file (tracks/<id>.json) with evenly spaced centreline points in metres.

Source data: https://github.com/bacinger/f1-circuits (MIT licence,
Copyright (c) 2019-2025 Tomislav Bacinger).

Usage:
  python3 tools/import_circuit.py tools/gb-1948.geojson silvermoor \
      "Silvermoor Circuit" --start-index 64 --half-width 7.5 --wall-offset 26

Game axes: +x = east, -z = north. The race direction follows the order of
the source coordinates (clockwise for Silverstone).
"""
import argparse
import json
import math

SPACING = 2.0
R_EARTH = 6371000.0


def to_metres(coords):
    lat0 = sum(p[1] for p in coords) / len(coords)
    lon0 = sum(p[0] for p in coords) / len(coords)
    k = math.cos(math.radians(lat0))
    return [((lon - lon0) * k * math.pi / 180 * R_EARTH,
             -(lat - lat0) * math.pi / 180 * R_EARTH) for lon, lat in coords]


def resample(pts, spacing):
    """Evenly spaced points along a closed polyline."""
    n = len(pts)
    segs = [(pts[i], pts[(i + 1) % n]) for i in range(n)]
    total = sum(math.dist(a, b) for a, b in segs)
    count = max(8, round(total / spacing))
    step = total / count
    out, seg_i, seg_pos, d = [], 0, 0.0, 0.0
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
    """Laplacian smoothing on a closed loop: rounds off the polygon corners
    of the source data without moving straights."""
    n = len(pts)
    for _ in range(passes):
        pts = [(pts[i][0] + alpha * ((pts[i - 1][0] + pts[(i + 1) % n][0]) / 2 - pts[i][0]),
                pts[i][1] + alpha * ((pts[i - 1][1] + pts[(i + 1) % n][1]) / 2 - pts[i][1]))
               for i in range(n)]
    return pts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("geojson")
    ap.add_argument("track_id")
    ap.add_argument("name")
    ap.add_argument("--start-index", type=int, default=0,
                    help="source vertex nearest the start/finish line")
    ap.add_argument("--start-offset", type=float, default=0.0,
                    help="metres to move the line forward from that vertex")
    ap.add_argument("--half-width", type=float, default=7.0)
    ap.add_argument("--wall-offset", type=float, default=24.0)
    ap.add_argument("--smooth-passes", type=int, default=40)
    ap.add_argument("--reverse", action="store_true",
                    help="the source runs against the race direction")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    g = json.load(open(a.geojson))
    feat = g["features"][0] if "features" in g else g
    coords = feat["geometry"]["coordinates"]
    if coords[0] == coords[-1]:
        coords = coords[:-1]
    if a.reverse:
        coords = coords[::-1]
    coords = coords[a.start_index:] + coords[:a.start_index]
    pts = to_metres(coords)
    pts = resample(pts, 1.0)
    pts = smooth(pts, a.smooth_passes)
    pts = resample(pts, SPACING)
    shift = int(round(a.start_offset / SPACING))
    pts = pts[shift:] + pts[:shift]
    length = sum(math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))

    out = {
        "id": a.track_id,
        "name": a.name,
        "real_length_m": feat.get("properties", {}).get("length"),
        "length_m": round(length, 1),
        "half_width": a.half_width,
        "wall_offset": a.wall_offset,
        "spacing": SPACING,
        "source": "bacinger/f1-circuits (MIT) " + feat.get("properties", {}).get("id", ""),
        "points": [[round(x, 2), round(z, 2)] for x, z in pts],
    }
    path = a.out or f"tracks/{a.track_id}.json"
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"{path}: {len(pts)} points, {length:.0f} m (official {out['real_length_m']} m)")


if __name__ == "__main__":
    main()
