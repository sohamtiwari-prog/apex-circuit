#!/usr/bin/env python3
"""Real elevation for each track, from F1 position telemetry.

Telemetry: TracingInsights (Apache-2.0), per-lap car positions x, y, z in
tenths of a metre (from the F1 live-timing feed via FastF1). For each circuit
the qualifying laps are aligned to our centreline (rotation, mirror, scale and
offset found by a coarse search, then ICP), the heights of every nearby
sample are pooled per centreline point (median), gaps filled, and the result
smoothed around the loop. Writes "elev" (metres, lowest point = 0) into the
track JSON, and turns the lap so it starts on the real timing line (where the
telemetry's lap distance is 0): points, racing line and elevation together.

    python3 tools/elevation_from_telemetry.py <TracingInsights 2025 checkout> [track ...]
"""
import glob
import json
import math
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

EVENTS = {
    "ardennes": "Belgian Grand Prix",
    "brianza": "Italian Grand Prix",
    "desert": "Bahrain Grand Prix",
    "entrelagos": "São Paulo Grand Prix",
    "riviera": "Monaco Grand Prix",
    "silvermoor": "British Grand Prix",
    "styria": "Austrian Grand Prix",
    "ile_royale": "Canadian Grand Prix",
    "marina": "Singapore Grand Prix",
    "pannonia": "Hungarian Grand Prix",
    "gulf": "Abu Dhabi Grand Prix",
}
HERE = os.path.dirname(os.path.abspath(__file__))
TRACKS = os.path.join(HERE, "..", "tracks")


def load_laps(root, event, real_len):
    laps = []
    for f in sorted(glob.glob(os.path.join(root, event, "Qualifying", "*", "*_tel.json"))):
        try:
            t = json.load(open(f))["tel"]
            d = np.array(t["distance"], float)
            xyz = np.array([t["x"], t["y"], t["z"]], float).T / 10.0
        except Exception:
            continue
        if len(d) < 200 or not np.isfinite(xyz).all():
            continue
        # A full flying lap only (out/in laps run through the pit lane).
        if abs(d.max() - real_len) > 0.04 * real_len:
            continue
        laps.append(xyz)
    return laps


def resample(path, step):
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    q = np.arange(0, s[-1], step)
    return np.stack([np.interp(q, s, path[:, k]) for k in range(path.shape[1])], 1)


def transform(pts, ang, mirror, scale, shift):
    p = pts.copy()
    if mirror:
        p[:, 0] = -p[:, 0]
    c, s = math.cos(ang), math.sin(ang)
    r = np.array([[c, -s], [s, c]])
    return (p @ r.T) * scale + shift


def register(lap_xy, ref_xy):
    """Similarity transform (with optional mirror) taking lap -> reference."""
    tree = cKDTree(ref_xy)
    lap_c = lap_xy - lap_xy.mean(0)
    best = None
    for mirror in (False, True):
        for deg in range(0, 360, 2):
            p = transform(lap_c, math.radians(deg), mirror, 1.0, ref_xy.mean(0))
            err = tree.query(p)[0].mean()
            if best is None or err < best[0]:
                best = (err, deg, mirror)
    _, deg, mirror = best
    # ICP refinement: rotation, scale and shift (Umeyama).
    src = lap_c.copy()
    if mirror:
        src[:, 0] = -src[:, 0]
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    R = np.array([[c, -s], [s, c]])
    sc = 1.0
    t = ref_xy.mean(0)
    for _ in range(60):
        cur = (src @ R.T) * sc + t
        d, idx = tree.query(cur)
        keep = d < np.percentile(d, 90) + 1e-6
        a = src[keep]
        b = ref_xy[idx[keep]]
        ma, mb = a.mean(0), b.mean(0)
        A, B = a - ma, b - mb
        U, S, Vt = np.linalg.svd(B.T @ A)
        D = np.eye(2)
        if np.linalg.det(U @ Vt) < 0:
            D[1, 1] = -1
        R = U @ D @ Vt
        sc = (S * np.diag(D)).sum() / (A ** 2).sum()
        t = mb - (ma @ R.T) * sc
    cur = (src @ R.T) * sc + t
    err = tree.query(cur)[0]
    return lambda xy: ((np.where([mirror, False], -1, 1) * (xy - lap_xy.mean(0))) @ R.T) * sc + t, err, sc


def smooth_loop(v, sigma_pts):
    n = len(v)
    k = int(sigma_pts * 3)
    w = np.exp(-0.5 * (np.arange(-k, k + 1) / sigma_pts) ** 2)
    w /= w.sum()
    ext = np.concatenate([v[-k:], v, v[:k]])
    return np.convolve(ext, w, mode="same")[k:k + n]


def main():
    root = sys.argv[1]
    only = sys.argv[2:] or list(EVENTS)
    for tid in only:
        path = os.path.join(TRACKS, tid + ".json")
        data = json.load(open(path))
        P = np.array(data["points"], float)[:, :2]
        n = len(P)
        spacing = float(data.get("spacing", 2.0))
        laps = load_laps(root, EVENTS[tid], float(data.get("real_length_m", data["length_m"])))
        if not laps:
            print(tid, "no laps")
            continue
        ref = resample(laps[0][:, :2], 4.0)
        fn, err, sc = register(ref, P)
        tree = cKDTree(P)
        pooled = [[] for _ in range(n)]
        used = 0
        starts = []
        for lap in laps:
            xy = fn(lap[:, :2])
            d, idx = tree.query(xy)
            if np.median(d) > 6.0:
                continue
            used += 1
            starts.append(idx[0])
            for k in np.nonzero(d < 9.0)[0]:
                pooled[idx[k]].append(lap[k, 2])
        z = np.array([np.median(p) if p else np.nan for p in pooled])
        ok = np.isfinite(z)
        ii = np.arange(n)
        z = np.interp(ii, ii[ok], z[ok], period=n)
        # Median first (kills one-off spikes where two stretches run close),
        # then a Gaussian.
        k = 7
        ext = np.concatenate([z[-k:], z, z[:k]])
        z = np.array([np.median(ext[i:i + 2 * k + 1]) for i in range(n)])        # ~12 m smoothing: keeps Eau Rouge sharp, removes sensor noise.
        z = smooth_loop(z, 6.0 / spacing * 2.0)
        # Real roads are built with a minimum vertical curve radius; sharper
        # wiggles are noise in the height data (and would launch cars).
        lim = spacing * spacing / 150.0
        for _ in range(4000):
            c = np.roll(z, 1) - 2 * z + np.roll(z, -1)
            bad = np.abs(c) > lim
            if not bad.any():
                break
            sm = 0.25 * np.roll(z, 1) + 0.5 * z + 0.25 * np.roll(z, -1)
            z = np.where(bad, sm, z)
        z -= z.min()
        grade = np.diff(np.concatenate([z, z[:1]])) / spacing
        # Start the lap on the real timing line.
        st = int(np.round(np.median(starts)))
        if st > n // 2:
            st -= n
        shift = int(st)
        if abs(shift) > 2:
            data["points"] = (np.roll(np.array(data["points"]), -shift, axis=0)).round(2).tolist()
            if "line" in data:
                data["line"] = np.roll(np.array(data["line"]), -shift).tolist()
            z = np.roll(z, -shift)
            grade = np.roll(grade, -shift)
        data["elev"] = [round(float(v), 2) for v in z]
        data["elev_source"] = "F1 position telemetry (TracingInsights 2025 qualifying, Apache-2.0), aligned and smoothed"
        json.dump(data, open(path, "w"), separators=(",", ":"))
        print("start moved %+5d m  " % (shift * spacing), end="")
        print("%-11s laps %3d/%3d  align rms %.1f m (scale %.3f)  coverage %3.0f%%  rise %5.1f m  max grade %+.1f%% / %+.1f%%"
              % (tid, used, len(laps), math.sqrt((err ** 2).mean()), sc, 100.0 * ok.mean(), z.max(), 100 * grade.max(), 100 * grade.min()))


if __name__ == "__main__":
    main()
