#!/usr/bin/env python3
"""V12 engine sound for the GP car: phase-locked engine-cycle tables.

How it sounds like an engine
  A V12 fires every 60 degrees of crank (12 firings per 720-degree cycle),
  alternating banks. Each firing is a sharp exhaust blowdown pulse into its
  bank's pipe; the open pipe end reflects an inverted pulse back (the "rip"
  of a race exhaust); sound leaving the tailpipe is roughly the derivative of
  the flow (the crisp bark). Fixed body/muffler resonances add weight; small
  fixed cylinder-to-cylinder and bank differences put energy below the firing
  note (the roar). Combustion noise rides on each pulse; a touch of
  saturation adds growl. Off throttle: smaller, softer pulses and more burble.

How it plays without smearing
  For each of several rpm points, a steady-state run of K engine cycles is
  rendered and resampled to exactly N samples per cycle, then circularly
  aligned so cylinder 1 fires at the same phase in every table. The game runs
  ONE engine phase and morphs between the two neighbouring tables at that
  same phase (instead of mixing two separately pitched loops, which phases
  and blurs). Pitch is exact for any rpm.

The GP car's 4000-12000 rpm is voiced as a V12 at 2300-8600 rpm (a V12 at
12000 rpm fires 1200 times a second and screams; this keeps the roar).

Writes data/audio/gp_<on|off>_<k>.pcm (16-bit, K*N samples each),
gp_crackle.pcm, gp_shift.pcm and gp.json. With --demo FILE.wav also renders a
demo using exactly the game's playback method.

    python3 tools/engine_sound.py [--demo out.wav]
"""
import json
import math
import os
import sys
import wave

import numpy as np
from scipy.signal import lfilter, butter, resample

SR = 32000
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "audio")
RPM_MAP = [[4000.0, 2300.0], [12000.0, 8600.0]]
TARGET_RPMS = [2000, 2500, 3100, 3800, 4600, 5500, 6500, 7600, 8800, 9600]
K = 8                      # engine cycles per table (cycle-to-cycle life)
N = 1024                   # samples per cycle in a table
RNG = np.random.default_rng(1993)

CYL_AMP = 1.0 + RNG.uniform(-0.06, 0.06, 12)
CYL_AMP[1::2] *= 0.92                    # bank B a touch quieter
CYL_JIT = RNG.uniform(-0.03, 0.03, 12)   # firing-time scatter (fraction of 60 deg)
PIPE_A = 0.95                            # header+pipe length (m), bank A
PIPE_B = 1.02


def resonator(x, f, q, gain):
    w = 2 * math.pi * f / SR
    alpha = math.sin(w) / (2 * q)
    b = np.array([alpha, 0, -alpha]) * gain
    a = np.array([1 + alpha, -2 * math.cos(w), 1 - alpha])
    return lfilter(b / a[0], a / a[0], x)


def pipe(x, length, r=0.55):
    """Open-ended pipe: the pulse plus an inverted echo every round trip."""
    d = max(1, int(round(2 * length / 343.0 * SR)))
    a = np.zeros(d + 1)
    a[0] = 1.0
    a[d] = r
    return lfilter([1.0], a, x)


def excitation(rpm, on_load, seed):
    """Pulses for K cycles, split by bank, plus noise envelope."""
    rng = np.random.default_rng(seed)
    cyc = SR * 120.0 / rpm
    n = int(round(cyc * K))
    banks = [np.zeros(n), np.zeros(n)]
    tau = (0.55e-3 if on_load else 1.1e-3)
    L = int(SR * tau * 10)
    t = np.arange(L) / SR
    pulse = (t / tau) * np.exp(1 - t / tau)
    if not on_load:
        pulse *= 0.32
    for c in range(K):
        cyc_var = 1.0 + rng.uniform(-0.06, 0.06)
        for j in range(12):
            pos = (c + (j + CYL_JIT[j]) / 12.0) * cyc
            i0 = int(pos)
            amp = CYL_AMP[j] * cyc_var * (1.0 + rng.uniform(-0.05, 0.05))
            if not on_load and rng.random() < 0.12:
                amp *= rng.uniform(1.5, 3.0)       # the odd overrun pop
            idx = (i0 + np.arange(L)) % n
            np.add.at(banks[j % 2], idx, pulse * amp)
    env = np.convolve(np.tile(banks[0] + banks[1], 2), np.ones(24) / 24, mode="same")[:n]
    return banks, env, rng


def render_cycles(rpm, on_load, seed):
    banks, env, rng = excitation(rpm, on_load, seed)
    n = len(env)
    reps = 5
    a = pipe(np.tile(banks[0], reps), PIPE_A)
    b = pipe(np.tile(banks[1], reps), PIPE_B)
    flow = a + b
    # Radiation from the tailpipe ~ derivative of the flow: the bark.
    rad = np.diff(flow, prepend=flow[0]) * 6.0
    x = 0.55 * rad + 0.45 * flow
    # Combustion / flow noise on every pulse (band-limited, not hiss).
    noise = rng.uniform(-1, 1, 2 * n)
    noise = lfilter(*butter(2, [350 / (SR / 2), 5000 / (SR / 2)], "band"), noise)[n:]
    x = x + np.tile(noise * np.abs(env), reps) * (0.55 if on_load else 1.2)
    y = 0.4 * x
    res = [(120, 1.6, 0.5), (240, 2.0, 0.6), (480, 2.4, 0.55), (950, 2.8, 0.45), (1900, 3.0, 0.3), (3400, 3.0, 0.12)]
    if not on_load:
        res = [(120, 1.6, 0.6), (240, 2.0, 0.55), (480, 2.4, 0.35), (950, 2.8, 0.2), (1900, 3.0, 0.1), (3400, 3.0, 0.03)]
    for f, q, g in res:
        y += resonator(x, f, q, g)
    y /= np.abs(y).max() + 1e-9
    drive = 1.8 if on_load else 1.2
    y = np.tanh(drive * y) / math.tanh(drive)
    y = lfilter(*butter(2, 80 / (SR / 2), "high"), y)          # no sub mud
    y = lfilter(*butter(2, 7000 / (SR / 2), "low"), y)         # no fizz
    loop = y[-n:]
    loop = loop / (np.sqrt(np.mean(loop ** 2)) + 1e-9)
    # Exactly N samples per cycle (periodic signal: FFT resampling is exact).
    return resample(loop, K * N)


def align(table, ref):
    """Circular shift of `table` that best matches `ref` (cycle-phase lock)."""
    c = np.fft.irfft(np.fft.rfft(ref) * np.conj(np.fft.rfft(table)), len(ref))
    return np.roll(table, int(np.argmax(c)))


def write_pcm(path, x):
    np.clip(np.round(x * 32767), -32768, 32767).astype("<i2").tofile(path)


def crackle(seconds=2.0):
    rng = np.random.default_rng(7)
    n = int(SR * seconds)
    x = np.zeros(n)
    t = 0
    while True:
        t += int(rng.exponential(SR * 0.07)) + 150
        if t >= n - 2000:
            break
        L = int(rng.uniform(0.003, 0.01) * SR)
        x[t:t + L] += rng.uniform(-1, 1, L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
    y = resonator(x, 380, 1.4, 1.0) + resonator(x, 1400, 1.8, 0.8) + 0.35 * x
    y = np.tanh(2.2 * y / (np.abs(y).max() + 1e-9))
    fade = int(SR * 0.01)
    y[:fade] *= np.linspace(0, 1, fade)
    y[-fade:] *= np.linspace(1, 0, fade)
    return y


def shift_crack():
    rng = np.random.default_rng(3)
    L = int(SR * 0.16)
    t = np.arange(L) / SR
    x = rng.uniform(-1, 1, L) * np.exp(-t / 0.012)
    y = resonator(x, 170, 1.8, 0.8) + resonator(x, 600, 2.2, 0.8) + resonator(x, 1700, 2.5, 0.5) + 0.3 * x
    return np.tanh(2.4 * y / (np.abs(y).max() + 1e-9)) * np.exp(-t / 0.045)


# ------------------------------------------------------------ playback (same as the game)

def play(tables_on, tables_off, rpms, srpm, load):
    """The game's method: one engine phase; morph neighbouring tables."""
    n = len(srpm)
    T = K * N
    lr = np.log(rpms)
    # Vectorised version of the per-sample loop in scripts/car_audio.gd.
    phase = np.cumsum(srpm / 120.0 / SR * N) % T
    l = np.log(srpm)
    k = np.clip(np.searchsorted(lr, l) - 1, 0, len(rpms) - 2)
    w = np.clip((l - lr[k]) / (lr[k + 1] - lr[k]), 0, 1)
    i0 = phase.astype(int)
    fr = phase - i0
    i1 = (i0 + 1) % T
    on_t = np.array(tables_on)
    off_t = np.array(tables_off)

    def look(tab, kk):
        return tab[kk, i0] * (1 - fr) + tab[kk, i1] * fr
    on = look(on_t, k) * (1 - w) + look(on_t, k + 1) * w
    off = look(off_t, k) * (1 - w) + look(off_t, k + 1) * w
    return on * load + off * (1 - load) * 0.6


def demo(path, tables_on, tables_off, rpms):
    dur = 9.0
    n = int(SR * dur)
    keys = [(0, 4300, 0.1), (0.8, 4300, 0.1), (1.0, 9000, 1), (1.9, 11800, 1), (1.95, 8600, 1), (2.9, 11800, 1),
            (2.95, 9000, 1), (4.0, 11900, 1), (4.05, 9400, 1), (5.2, 12000, 1), (5.4, 11800, 0.0),
            (7.2, 6500, 0.0), (7.3, 8200, 0.25), (7.5, 7000, 0.0), (8.2, 5200, 0.0), (9.0, 4300, 0.1)]
    tt = np.arange(n) / SR
    kt = [k[0] for k in keys]
    game = np.interp(tt, kt, [k[1] for k in keys])
    load = np.interp(tt, kt, [k[2] for k in keys])
    srpm = RPM_MAP[0][1] + (game - RPM_MAP[0][0]) * (RPM_MAP[1][1] - RPM_MAP[0][1]) / (RPM_MAP[1][0] - RPM_MAP[0][0])
    out = play(tables_on, tables_off, np.array(rpms), srpm, load)
    out *= 0.55 + 0.45 * (game - 4000) / 8000
    out = out / np.abs(out).max() * 0.92
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(np.clip(out * 32767, -32768, 32767).astype("<i2").tobytes())
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    tables_on, tables_off, rpms = [], [], []
    for k, rpm in enumerate(TARGET_RPMS):
        on = render_cycles(rpm, True, 100 + k)
        off = render_cycles(rpm, False, 200 + k)
        # Phase-lock every table to its neighbour's firing pattern.
        if tables_on:
            on = align(on, tables_on[-1])
            off = align(off, tables_off[-1])
        else:
            off = align(off, on)
        tables_on.append(on)
        tables_off.append(off)
        rpms.append(float(rpm))
    peak = max(np.abs(np.concatenate(tables_on + tables_off)).max(), 1e-9)
    meta = {"sample_rate": SR, "cycles": K, "per_cycle": N, "rpm_map": RPM_MAP, "layers": []}
    for k, rpm in enumerate(rpms):
        write_pcm(os.path.join(OUT, "gp_on_%d.pcm" % k), tables_on[k] / peak * 0.95)
        write_pcm(os.path.join(OUT, "gp_off_%d.pcm" % k), tables_off[k] / peak * 0.95)
        meta["layers"].append({"rpm": rpm, "on": "gp_on_%d.pcm" % k, "off": "gp_off_%d.pcm" % k})
        sr_k = N * rpm / 120.0
        spec = np.abs(np.fft.rfft(tables_on[k])) ** 2
        freqs = np.fft.rfftfreq(len(tables_on[k]), 1 / sr_k)
        cen = (np.sqrt(spec) * freqs).sum() / np.sqrt(spec).sum()
        bands = [(0, 250), (250, 1000), (1000, 3000), (3000, 99999)]
        share = [spec[(freqs >= a) & (freqs < b)].sum() / spec.sum() * 100 for a, b in bands]
        corr = np.corrcoef(tables_on[k], tables_on[k - 1])[0, 1] if k else 1.0
        print("table %d: %5.0f rpm  firing %4.0f Hz  centroid %4.0f Hz  <250 %2.0f%%  0.25-1k %2.0f%%  1-3k %2.0f%%  >3k %2.0f%%  match prev %.2f"
              % (k, rpm, rpm / 10, cen, *share, corr))
    write_pcm(os.path.join(OUT, "gp_crackle.pcm"), crackle() * 0.7)
    write_pcm(os.path.join(OUT, "gp_shift.pcm"), shift_crack() * 0.8)
    meta["crackle"] = "gp_crackle.pcm"
    meta["shift"] = "gp_shift.pcm"
    json.dump(meta, open(os.path.join(OUT, "gp.json"), "w"), indent=1)
    if "--demo" in sys.argv:
        demo(sys.argv[sys.argv.index("--demo") + 1], tables_on, tables_off, rpms)
        print("demo written")


if __name__ == "__main__":
    main()
