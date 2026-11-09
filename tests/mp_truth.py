"""How far from where it really is each car is drawn on the other phone.
Reads truth_host.csv and truth_client.csv written by tests/mp_test.gd (with
TRUTH_DIR set): every 0.1 s on the shared clock, every car's position, T for
a car this phone drives (the truth), D for one it draws from the network.
    python3 tests/mp_truth.py <dir> [max_p95_m]
"""
import bisect
import sys
from collections import defaultdict

d = sys.argv[1]
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0


def load(role):
    rows = []
    for line in open("%s/truth_%s.csv" % (d, role)):
        t, slot, kind, x, y, z, near, pit = line.strip().split(",")
        rows.append((float(t), int(slot), kind, float(x), float(y), float(z), near == "1", int(pit)))
    return rows


def truth_of(rows):
    tr = defaultdict(list)
    for t, slot, kind, x, y, z, near, pit in rows:
        if kind == "T":
            tr[slot].append((t, x, y, z))
    return tr


def at(series, t):
    ts = [s[0] for s in series]
    k = bisect.bisect_left(ts, t)
    if k == 0 or k >= len(series):
        return None
    a, b = series[k - 1], series[k]
    if b[0] - a[0] > 0.5:
        return None
    f = (t - a[0]) / (b[0] - a[0])
    return tuple(a[i] + (b[i] - a[i]) * f for i in (1, 2, 3))


ok = True
roles = {"host": "client", "client": "host"}
for viewer, other in roles.items():
    drawn = load(viewer)
    truth = truth_of(load(other))
    errs, near_errs = [], []
    for t, slot, kind, x, y, z, near, pit in drawn:
        if kind != "D" or slot not in truth or pit > 0:
            continue
        p = at(truth[slot], t)
        if p is None:
            continue
        e = ((x - p[0]) ** 2 + (z - p[2]) ** 2) ** 0.5
        if e > 30:
            continue                       # (a reset or the pits: not a drawing error)
        errs.append(e)
        if near:
            near_errs.append(e)
    for name, es in (("all cars", errs), ("cars within 60 m of you", near_errs)):
        if not es:
            continue
        es.sort()
        p50, p95, mx = es[len(es) // 2], es[int(len(es) * 0.95)], es[-1]
        print("  %-6s draws %-24s off from where they really are by: median %.2f m, 95%% %.2f m, worst %.1f m (%d samples)" % (viewer, name, p50, p95, mx, len(es)))
        if limit and name.startswith("cars within") and p95 > limit:
            ok = False
print("ALL CHECKS PASSED" if ok else "CHECK FAILED: cars near you drawn too far from where they are")
sys.exit(0 if ok else 1)
