"""Draws the sponsors' logos (data/sponsors.json) into the textures the game
uses. Every brand is made up; the logos are a mark drawn here from simple
shapes plus a wordmark in one of the game's own fonts.

    python3 tools/make_sponsors.py

textures/sponsor_logos.png    2048 x 1792: two sets of 512 x 128 cells, four
                              to a row in the brands' order. Rows 0-6: the
                              logo in white on clear (tinted on the car);
                              rows 7-13: the logo on its own colours (a
                              sticker).
textures/sponsor_boards.png   2048 x 2048: 1024 x 128 advertising boards,
                              two to a row: one per brand, then a few
                              reversed-colour versions of the biggest names.
textures/tyre_strip.png       2048 x 64: the tyre maker's name, twice round
                              the sidewall (white on black).
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 2                                     # drawn at twice the size, then scaled down
CELL = (512, 128)
BOARD = (1024, 128)
LOGO_ROWS = 7
# Reversed boards after the brands' own: white ground, the brand's colour as ink.
REVERSED = ["apex", "falco", "aurum", "orbis", "northwind", "trident"]


def hexcol(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def font(kind, px):
    if kind == "saira":
        return ImageFont.truetype(os.path.join(ROOT, "fonts/SairaCondensed-ExtraBold.ttf"), px)
    if kind == "barlow":
        return ImageFont.truetype(os.path.join(ROOT, "fonts/BarlowSemiCondensed-ExtraBold.ttf"), px)
    if kind == "light":
        return ImageFont.truetype(os.path.join(ROOT, "fonts/BarlowSemiCondensed-SemiBold.ttf"), px)
    f = ImageFont.truetype(os.path.join(ROOT, "fonts/Archivo-Variable.ttf"), px)
    f.set_variation_by_axes([850, 125])
    return f


# ------------------------------------------------------------------ marks
# Each draws in a square: top-left (x, y), side s, on an "L" mask.

def mark(d, kind, x, y, s):
    W = 255
    c = (x + s / 2, y + s / 2)
    if kind == "chevrons":
        for k in range(2):
            o = k * s * 0.34
            d.polygon([(x + o, y + s * 0.1), (x + o + s * 0.36, y + s * 0.1), (x + o + s * 0.72, y + s * 0.5),
                       (x + o + s * 0.36, y + s * 0.9), (x + o, y + s * 0.9), (x + o + s * 0.36, y + s * 0.5)], fill=W)
    elif kind == "wing":
        d.polygon([(x, y + s * 0.85), (x + s, y + s * 0.08), (x + s * 0.78, y + s * 0.5), (x + s * 0.98, y + s * 0.42),
                   (x + s * 0.62, y + s * 0.92)], fill=W)
    elif kind == "bolt":
        d.polygon([(x + s * 0.62, y), (x + s * 0.12, y + s * 0.58), (x + s * 0.46, y + s * 0.58), (x + s * 0.34, y + s),
                   (x + s * 0.9, y + s * 0.38), (x + s * 0.55, y + s * 0.38)], fill=W)
    elif kind == "swoosh":
        pts = []
        for i in range(25):
            t = i / 24
            pts.append((x + s * t, y + s * (0.78 - 0.55 * math.sin(t * math.pi * 0.9))))
        for i in range(24, -1, -1):
            t = i / 24
            pts.append((x + s * t, y + s * (0.98 - 0.42 * math.sin(t * math.pi * 0.9) + 0.0 * t)))
        d.polygon(pts, fill=W)
    elif kind == "crown":
        d.polygon([(x + s * 0.05, y + s * 0.82), (x + s * 0.05, y + s * 0.25), (x + s * 0.3, y + s * 0.55), (x + s * 0.5, y + s * 0.12),
                   (x + s * 0.7, y + s * 0.55), (x + s * 0.95, y + s * 0.25), (x + s * 0.95, y + s * 0.82)], fill=W)
        d.rectangle([x + s * 0.05, y + s * 0.88, x + s * 0.95, y + s * 0.98], fill=W)
    elif kind == "slash":
        for k in range(3):
            o = k * s * 0.3
            d.polygon([(x + o + s * 0.3, y + s * 0.05), (x + o + s * 0.48, y + s * 0.05), (x + o + s * 0.18, y + s * 0.95), (x + o, y + s * 0.95)], fill=W)
    elif kind == "orbit":
        d.ellipse([x + s * 0.32, y + s * 0.32, x + s * 0.68, y + s * 0.68], fill=W)
        d.ellipse([x, y + s * 0.2, x + s, y + s * 0.8], outline=W, width=max(2, int(s * 0.09)))
    elif kind == "peaks":
        d.polygon([(x, y + s * 0.92), (x + s * 0.38, y + s * 0.18), (x + s * 0.58, y + s * 0.55), (x + s * 0.72, y + s * 0.34),
                   (x + s, y + s * 0.92)], fill=W)
    elif kind == "trident":
        w = s * 0.12
        d.rectangle([c[0] - w / 2, y + s * 0.2, c[0] + w / 2, y + s], fill=W)
        d.rectangle([x + s * 0.12, y + s * 0.5, x + s * 0.88, y + s * 0.5 + w], fill=W)
        for px in (x + s * 0.12, c[0] - w / 2, x + s * 0.88 - w):
            d.rectangle([px, y + s * 0.18, px + w, y + s * 0.6], fill=W)
            d.polygon([(px - w * 0.3, y + s * 0.2), (px + w * 0.5, y), (px + w * 1.3, y + s * 0.2)], fill=W)
    elif kind == "arrow":
        d.polygon([(x, y + s * 0.3), (x + s * 0.55, y + s * 0.3), (x + s * 0.55, y + s * 0.08), (x + s, y + s * 0.5),
                   (x + s * 0.55, y + s * 0.92), (x + s * 0.55, y + s * 0.7), (x, y + s * 0.7)], fill=W)
    elif kind in ("hexagon", "gear"):
        n = 6 if kind == "hexagon" else 16
        pts = []
        for i in range(n):
            a = math.pi * 2 * i / n + math.pi / 6
            r = s * 0.5 if (kind == "hexagon" or i % 2 == 0) else s * 0.4
            pts.append((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r))
        d.polygon(pts, fill=W)
        hole = s * (0.22 if kind == "hexagon" else 0.17)
        d.ellipse([c[0] - hole, c[1] - hole, c[0] + hole, c[1] + hole], fill=0)
    elif kind == "petals":
        for i in range(5):
            a = math.pi * 2 * i / 5 - math.pi / 2
            px, py = c[0] + math.cos(a) * s * 0.27, c[1] + math.sin(a) * s * 0.27
            d.ellipse([px - s * 0.21, py - s * 0.21, px + s * 0.21, py + s * 0.21], fill=W)
        d.ellipse([c[0] - s * 0.1, c[1] - s * 0.1, c[0] + s * 0.1, c[1] + s * 0.1], fill=0)
    elif kind == "diamond":
        d.polygon([(c[0], y), (x + s, c[1]), (c[0], y + s), (x, c[1])], fill=W)
        d.polygon([(c[0], y + s * 0.3), (x + s * 0.7, c[1]), (c[0], y + s * 0.7), (x + s * 0.3, c[1])], fill=0)
    elif kind == "square":
        d.rectangle([x + s * 0.06, y + s * 0.06, x + s * 0.94, y + s * 0.94], fill=W)
        d.rectangle([x + s * 0.3, y + s * 0.3, x + s * 0.7, y + s * 0.7], fill=0)
        d.rectangle([x + s * 0.06, y + s * 0.44, x + s * 0.3, y + s * 0.56], fill=0)
    elif kind == "bean":
        d.ellipse([x + s * 0.12, y, x + s * 0.88, y + s], fill=W)
        d.line([(c[0] + s * 0.06, y + s * 0.08), (c[0] - s * 0.1, c[1]), (c[0] + s * 0.06, y + s * 0.92)], fill=0, width=max(2, int(s * 0.08)))
    elif kind == "bars":
        for k in range(4):
            d.rectangle([x + s * 0.08 * k, y + s * (0.08 + 0.23 * k), x + s * (0.68 + 0.08 * k), y + s * (0.24 + 0.23 * k)], fill=W)
    elif kind == "ring":
        d.ellipse([x, y, x + s, y + s], fill=W)
        d.ellipse([x + s * 0.24, y + s * 0.24, x + s * 0.76, y + s * 0.76], fill=0)
        d.rectangle([x + s * 0.62, y + s * 0.62, x + s, y + s], fill=0)
    elif kind == "drop":
        d.ellipse([x + s * 0.18, y + s * 0.36, x + s * 0.82, y + s], fill=W)
        d.polygon([(c[0], y), (x + s * 0.2, y + s * 0.62), (x + s * 0.8, y + s * 0.62)], fill=W)
    elif kind == "beak":
        d.polygon([(x, y + s * 0.2), (x + s, y + s * 0.5), (x, y + s * 0.8), (x + s * 0.25, y + s * 0.5)], fill=W)
    elif kind == "shield":
        d.polygon([(x + s * 0.1, y + s * 0.05), (x + s * 0.9, y + s * 0.05), (x + s * 0.9, y + s * 0.5), (c[0], y + s),
                   (x + s * 0.1, y + s * 0.5)], fill=W)
        d.polygon([(c[0], y + s * 0.18), (x + s * 0.75, y + s * 0.18), (x + s * 0.75, y + s * 0.48), (c[0], y + s * 0.8)], fill=0)
    elif kind == "star":
        pts = []
        for i in range(10):
            a = math.pi * 2 * i / 10 - math.pi / 2
            r = s * 0.5 if i % 2 == 0 else s * 0.21
            pts.append((c[0] + math.cos(a) * r, c[1] + s * 0.04 + math.sin(a) * r))
        d.polygon(pts, fill=W)
    elif kind == "waves":
        hs = [0.4, 0.75, 1.0, 0.6, 0.85]
        for k, h in enumerate(hs):
            bx = x + s * (0.02 + k * 0.2)
            d.rounded_rectangle([bx, c[1] - s * h / 2, bx + s * 0.13, c[1] + s * h / 2], radius=s * 0.06, fill=W)
    elif kind == "wave":
        w = max(2, int(s * 0.13))
        for k in range(2):
            pts = [(x + s * i / 20, y + s * (0.38 + 0.36 * k) + math.sin(i / 20 * math.pi * 2) * s * 0.12) for i in range(21)]
            d.line(pts, fill=W, width=w, joint="curve")
    elif kind == "gem":
        d.polygon([(x + s * 0.2, y + s * 0.12), (x + s * 0.8, y + s * 0.12), (x + s, y + s * 0.4), (c[0], y + s), (x, y + s * 0.4)], fill=W)
        d.line([(x, y + s * 0.4), (x + s, y + s * 0.4)], fill=0, width=max(2, int(s * 0.05)))


# ------------------------------------------------------------------ logos

def draw_logo(b, w, h, scale=1.0):
    """The brand's logo centred in a w x h mask (already at SS scale)."""
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    sub = b.get("sub", "")
    name_px = int(h * (0.6 if sub else 0.74) * scale)
    f = font(b["font"], name_px)
    nb = f.getbbox(b["name"], anchor="ls")
    name_w = nb[2] - nb[0]
    cap = -nb[1]
    sub_px = int(name_px * 0.42)
    fs = font("barlow", sub_px)
    track = sub_px * 0.18
    sub_w = 0
    if sub:
        sb = fs.getbbox(sub, anchor="ls")
        sub_w = (sb[2] - sb[0]) + track * (len(sub) - 1)
    has_mark = b.get("mark", "") != ""
    ms = cap * (1.55 if sub else 1.15)
    gap = cap * 0.28
    text_w = max(name_w, sub_w)
    total = text_w + ((ms + gap) if has_mark else 0)
    k = min(1.0, (w * 0.92) / total)
    if k < 1.0:
        return draw_logo(b, w, h, scale * k * 0.99)
    block_h = cap + (cap * 0.2 + sub_px * 0.72 if sub else 0)
    top = (h - block_h) / 2
    x0 = (w - total) / 2
    if has_mark:
        mark(d, b["mark"], x0, top + (block_h - ms) / 2, ms)
        x0 += ms + gap
    text = Image.new("L", (w, h), 0)
    td = ImageDraw.Draw(text)
    base = top + cap
    nx = x0 + (text_w - name_w) / 2 if sub and sub_w > name_w else x0
    td.text((nx - nb[0], base), b["name"], font=f, fill=255, anchor="ls")
    if sub:
        sx = x0 + (text_w - sub_w) / 2
        sy = base + cap * 0.2 + sub_px * 0.72
        for ch in sub:
            td.text((sx, sy), ch, font=fs, fill=255, anchor="ls")
            sx += fs.getlength(ch) + track
    if b.get("italic"):
        # Lean the lettering forward about its baseline.
        sh = 0.2
        text = text.transform(text.size, Image.AFFINE, (1, sh, -sh * base, 0, 1, 0), resample=Image.BICUBIC)
    m.paste(255, (0, 0), text)
    return m


def down(img, size):
    return img.resize(size, Image.LANCZOS)


def mono(b):
    w, h = CELL[0] * SS, CELL[1] * SS
    pad = 10 * SS
    m = Image.new("L", (w, h), 0)
    m.paste(draw_logo(b, w - pad * 2, h - pad * 2), (pad, pad))
    m = down(m, CELL)
    out = Image.new("RGBA", CELL, (255, 255, 255, 0))
    out.putalpha(m)
    return out


def coloured(b, size, fg=None, bg=None, scale=1.0, band=True):
    w, h = size[0] * SS, size[1] * SS
    fgc = hexcol(fg or b["fg"])
    bgc = hexcol(bg or b["bg"])
    img = Image.new("RGB", (w, h), bgc)
    d = ImageDraw.Draw(img)
    if band:
        # A slim band of the ink colour along the bottom edge.
        d.rectangle([0, h - h * 0.09, w, h], fill=tuple(int(a * 0.55 + c * 0.45) for a, c in zip(bgc, fgc)))
    pad_x = int(h * 0.3)
    pad_y = int(h * 0.12)
    m = draw_logo(b, w - pad_x * 2, h - pad_y * 2 - int(h * 0.05), scale)
    img.paste(fgc, (pad_x, pad_y), m)
    return down(img, size)


def main():
    brands = json.load(open(os.path.join(ROOT, "data/sponsors.json")))["brands"]
    ids = [b["id"] for b in brands]
    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    per_row = 2048 // CELL[0]
    assert len(brands) <= per_row * LOGO_ROWS
    logos = Image.new("RGBA", (2048, CELL[1] * LOGO_ROWS * 2), (255, 255, 255, 0))
    for i, b in enumerate(brands):
        cx, cy = (i % per_row) * CELL[0], (i // per_row) * CELL[1]
        logos.paste(mono(b), (cx, cy))
        logos.paste(coloured(b, CELL).convert("RGBA"), (cx, cy + CELL[1] * LOGO_ROWS))
    logos.save(os.path.join(ROOT, "textures/sponsor_logos.png"), optimize=True)

    boards = Image.new("RGB", (2048, 2048), (20, 20, 20))
    k = 0
    for b in brands:
        boards.paste(coloured(b, BOARD, scale=0.92), ((k % 2) * BOARD[0], (k // 2) * BOARD[1]))
        k += 1
    for rid in REVERSED:
        b = brands[ids.index(rid)]
        ink = b["bg"] if hexcol(b["bg"]) != (255, 255, 255) else b["fg"]
        if sum(hexcol(ink)) < 60:
            ink = "#111111"
        boards.paste(coloured(b, BOARD, fg=ink, bg="#ffffff", scale=0.92), ((k % 2) * BOARD[0], (k // 2) * BOARD[1]))
        k += 1
    boards.save(os.path.join(ROOT, "textures/sponsor_boards.png"), optimize=True)

    # The tyre maker's name round the sidewall: big name, smaller line after.
    tw, th = 2048 * SS, 64 * SS
    strip = Image.new("L", (tw, th), 0)
    tyre = brands[ids.index("falco")]
    for rep in range(2):
        x = rep * tw // 2 + 120 * SS
        m = draw_logo(tyre, 330 * SS, th)
        strip.paste(255, (x, 0), m)
        f = font("barlow", int(th * 0.42))
        f2 = font("light", int(th * 0.32))
        tx = x + 360 * SS
        ImageDraw.Draw(strip).text((tx, th * 0.68), "CORSA", font=f, fill=255, anchor="ls")
        ImageDraw.Draw(strip).text((tx + f.getlength("CORSA ") + 8 * SS, th * 0.68), "RACE SLICK  ·  305/670 R18", font=f2, fill=200, anchor="ls")
    strip = down(strip, (2048, 64))
    strip.save(os.path.join(ROOT, "textures/tyre_strip.png"), optimize=True)
    print("brands:", len(brands), "boards:", k)


if __name__ == "__main__":
    main()
