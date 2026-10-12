#!/usr/bin/env python3
"""Draws the Play Games achievement and leaderboard icons (512x512 PNG).

    python3 tool/generate_pgs_icons.py

Writes docs/store/play-games/{achievements,leaderboards}/*.png and MAP.md
(which icon goes with which achievement / leaderboard). Every icon shares
the game's look: a dark glowing badge inside the four-color ring, with a
glyph in the middle. Play Games makes the grey "locked" version itself.
Needs Pillow and numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "store", "play-games")

RED = (0xFF, 0x3D, 0x6E)
BLUE = (0x2F, 0x8B, 0xFF)
YELLOW = (0xFF, 0xC9, 0x28)
GREEN = (0x22, 0xD5, 0x8B)
ORANGE = (0xFF, 0x7A, 0x2F)
PURPLE = (0xB0, 0x6C, 0xFF)
CYAN = (0x7F, 0xE7, 0xFF)
GOLD = (0xFF, 0xD5, 0x4A)
WHITE = (255, 255, 255)
INK = (0x0B, 0x0C, 0x18)

SIZE = 512
SS = 3
S = SIZE * SS
C = S / 2


def font(px):
    for path in (
        "/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf",
        os.path.expanduser("~/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf"),
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    return ImageFont.load_default()


def mix(a, b, k):
    return tuple(round(x + (y - x) * k) for x, y in zip(a, b))


def background(accent):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.clip(np.sqrt((x - C) ** 2 + (y - C * 0.92) ** 2) / (S * 0.62), 0, 1)[..., None]
    inner = np.array(mix((0x2E, 0x26, 0x5C), accent, 0.35), np.float32)
    outer = np.array((0x0B, 0x0C, 0x18), np.float32)
    rgb = inner + (outer - inner) * d ** 1.1
    return Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")


def ring(img):
    """The game's four-color ring around the badge."""
    r, w = S * 0.40, S * 0.05
    for i, color in enumerate((RED, YELLOW, BLUE, GREEN)):
        glow = Image.new("RGBA", (S, S), color + (0,))
        ImageDraw.Draw(glow).arc([C - r - w, C - r - w, C + r + w, C + r + w],
                                 -135 + i * 90 + 4, -45 + i * 90 - 4,
                                 fill=color + (110,), width=round(w * 1.8))
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.012)))
    d = ImageDraw.Draw(img)
    for i, color in enumerate((RED, YELLOW, BLUE, GREEN)):
        d.arc([C - r - w / 2, C - r - w / 2, C + r + w / 2, C + r + w / 2],
              -135 + i * 90 + 4, -45 + i * 90 - 4, fill=color + (255,), width=round(w))


def glow_disc(img, color, radius, alpha=120):
    g = Image.new("RGBA", (S, S), color + (0,))
    ImageDraw.Draw(g).ellipse([C - radius, C - radius, C + radius, C + radius], fill=color + (alpha,))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(radius * 0.35)))


def text(img, s, size, color=WHITE, dy=0.0, shadow=True):
    f = font(round(size * SS))
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), s, font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = C - w / 2 - box[0], C - h / 2 - box[1] + dy * S
    if shadow:
        d.text((x, y + S * 0.012), s, font=f, fill=INK + (200,))
    d.text((x, y), s, font=f, fill=color + (255,))


def poly(img, pts, fill, outline=None, width=0):
    d = ImageDraw.Draw(img)
    d.polygon([(C + x * S, C + y * S) for x, y in pts], fill=fill + (255,))
    if outline:
        d.line([(C + x * S, C + y * S) for x, y in pts + [pts[0]]], fill=outline + (255,),
               width=round(width * S), joint="curve")


def circle(img, cx, cy, r, fill=None, outline=None, width=0):
    d = ImageDraw.Draw(img)
    box = [C + (cx - r) * S, C + (cy - r) * S, C + (cx + r) * S, C + (cy + r) * S]
    d.ellipse(box, fill=fill + (255,) if fill else None,
              outline=outline + (255,) if outline else None, width=round(width * S))


def ball(img, cx, cy, r, color):
    """A glossy ball like the one in the game."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    px, py, pr = C + cx * S, C + cy * S, r * S
    d = np.clip(np.sqrt((x - (px - pr * 0.38)) ** 2 + (y - (py - pr * 0.42)) ** 2) / (pr * 1.55), 0, 1)[..., None]
    light = np.array(mix(color, WHITE, 0.5), np.float32)
    mid = np.array(color, np.float32)
    dark = np.array(mix(color, INK, 0.45), np.float32)
    rgb = np.where(d < 0.45, light + (mid - light) * (d / 0.45), mid + (dark - mid) * ((d - 0.45) / 0.55))
    a = ((np.sqrt((x - px) ** 2 + (y - py) ** 2) <= pr) * 255.0)[..., None]
    img.alpha_composite(Image.fromarray(np.concatenate([rgb, a], -1).astype(np.uint8), "RGBA"))
    circle(img, cx - r * 0.38, cy - r * 0.44, r * 0.13, fill=WHITE)


def star(img, cx, cy, r, color, inner=0.45):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    poly(img, pts, color, outline=mix(color, INK, 0.4), width=0.008)


def _drop(cx, cy, s, tilt=0.0):
    """A teardrop pointing up (rotated by [tilt] radians): one flame tongue."""
    pts = []
    for i in range(80):
        t = i / 79 * 2 * math.pi
        x = s * 0.62 * math.sin(t) * math.sin(t / 2) ** 1.3
        y = -s * math.cos(t) * (1.0 if math.cos(t) > 0 else 0.62)
        x, y = x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt)
        pts.append((cx + x, cy + y))
    return pts


def flame(img, cx, cy, s, color, core):
    for tilt, dx, k in ((-0.45, -0.38, 0.62), (0.45, 0.38, 0.62), (0, 0, 1.0)):
        poly(img, _drop(cx + dx * s, cy + s * (1 - k) * 0.55, s * k, tilt), color)
    poly(img, _drop(cx, cy + s * 0.3, s * 0.55), core)
    poly(img, _drop(cx, cy + s * 0.5, s * 0.25), (255, 245, 215))


# ---------------------------------------------------------------- glyphs


def g_first_lock(img):
    ball(img, 0, 0.02, 0.17, YELLOW)
    # Padlock on the ball's lower right.
    d = ImageDraw.Draw(img)
    x0, y0 = C + 0.06 * S, C + 0.05 * S
    d.rounded_rectangle([x0, y0, x0 + 0.17 * S, y0 + 0.14 * S], radius=0.025 * S, fill=WHITE + (255,),
                        outline=INK + (255,), width=round(0.01 * S))
    d.arc([x0 + 0.03 * S, y0 - 0.09 * S, x0 + 0.14 * S, y0 + 0.04 * S], 180, 360,
          fill=WHITE + (255,), width=round(0.025 * S))
    circle(img, (x0 - C) / S + 0.085, (y0 - C) / S + 0.065, 0.02, fill=INK)


def g_number(label, color, sub=None, size=150):
    def draw(img):
        glow_disc(img, color, S * 0.22, 90)
        text(img, label, size, color, dy=-0.02 if sub else 0)
        if sub:
            text(img, sub, 46, WHITE, dy=0.15)
    return draw


def g_score(label, color, crown=False):
    def draw(img):
        glow_disc(img, color, S * 0.22, 100)
        if crown:
            poly(img, [(-0.13, -0.13), (-0.13, -0.21), (-0.065, -0.165), (0, -0.23),
                       (0.065, -0.165), (0.13, -0.21), (0.13, -0.13)], GOLD,
                 outline=mix(GOLD, INK, 0.45), width=0.008)
        text(img, label, 128 if len(label) < 4 else 104, color, dy=0.03 if crown else 0)
    return draw


def g_streak(n):
    def draw(img):
        for r, col in ((0.24, RED), (0.17, WHITE), (0.10, RED)):
            circle(img, 0, -0.02, r, fill=col)
        circle(img, 0, -0.02, 0.04, fill=WHITE)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([C - 0.11 * S, C + 0.13 * S, C + 0.11 * S, C + 0.25 * S], radius=0.04 * S,
                            fill=INK + (235,), outline=WHITE + (255,), width=round(0.008 * S))
        text(img, n, 64, GOLD, dy=0.19, shadow=False)
    return draw


def g_fever(img):
    glow_disc(img, ORANGE, S * 0.24, 130)
    flame(img, 0, 0.0, 0.22, ORANGE, GOLD)


def g_combo(img):
    glow_disc(img, (0xFF, 0x4D, 0x8D), S * 0.22, 110)
    text(img, "x5", 170, (0xFF, 0x7B, 0xAA))


def g_boss(n):
    def draw(img):
        cols = (RED, YELLOW, BLUE, GREEN)
        for i, col in enumerate(cols):
            ball(img, -0.18 + i * 0.12, -0.06 if not n else -0.09, 0.055, col)
        if n:
            text(img, n, 96, WHITE, dy=0.1)
        else:
            text(img, "?", 120, WHITE, dy=0.1)
    return draw


def g_stage3(img):
    glow_disc(img, ORANGE, S * 0.2, 100)
    for i, h in enumerate((0.1, 0.18, 0.26)):
        x = -0.17 + i * 0.12
        poly(img, [(x, 0.15), (x + 0.1, 0.15), (x + 0.1, 0.15 - h), (x, 0.15 - h)],
             (ORANGE, GOLD, YELLOW)[i])
    star(img, 0.12, -0.16, 0.06, WHITE)


def g_void(img):
    for r, a in ((0.24, 60), (0.19, 110), (0.14, 170)):
        circle(img, 0, 0, r, outline=PURPLE, width=0.02)
    glow_disc(img, PURPLE, S * 0.13, 160)
    circle(img, 0, 0, 0.09, fill=(0x05, 0x03, 0x10))
    text(img, "6", 70, (0xE0, 0xC8, 0xFF))


def g_not(img):
    ball(img, 0, -0.04, 0.16, GREEN)
    d = ImageDraw.Draw(img)
    for a, b in (((-0.12, -0.16), (0.12, 0.08)), ((0.12, -0.16), (-0.12, 0.08))):
        d.line([(C + a[0] * S, C + a[1] * S), (C + b[0] * S, C + b[1] * S)], fill=INK + (255,), width=round(0.06 * S))
        d.line([(C + a[0] * S, C + a[1] * S), (C + b[0] * S, C + b[1] * S)], fill=WHITE + (255,), width=round(0.032 * S))
    text(img, "50", 64, WHITE, dy=0.2)


def g_greedy(img):
    glow_disc(img, GOLD, S * 0.22, 130)
    circle(img, 0, -0.03, 0.17, fill=GOLD, outline=(0xE0, 0xA8, 0x00), width=0.025)
    circle(img, 0, -0.03, 0.12, outline=(0xE0, 0xA8, 0x00), width=0.012)
    text(img, "+5", 88, (0x8A, 0x5A, 0x00), dy=-0.03, shadow=False)
    text(img, "25", 64, WHITE, dy=0.2)


def g_runs(img):
    d = ImageDraw.Draw(img)
    r = 0.2 * S
    d.arc([C - r, C - r, C + r, C + r], -60, 240, fill=CYAN + (255,), width=round(0.04 * S))
    a = math.radians(-60)
    tx, ty = C + math.cos(a) * r, C + math.sin(a) * r
    d.polygon([(tx + 0.05 * S, ty - 0.02 * S), (tx - 0.04 * S, ty - 0.07 * S), (tx - 0.02 * S, ty + 0.05 * S)],
              fill=CYAN + (255,))
    text(img, "100", 84, WHITE)


def g_calendar(label, color):
    def draw(img):
        d = ImageDraw.Draw(img)
        x0, y0, x1, y1 = C - 0.19 * S, C - 0.17 * S, C + 0.19 * S, C + 0.2 * S
        d.rounded_rectangle([x0, y0, x1, y1], radius=0.04 * S, fill=WHITE + (255,))
        d.rounded_rectangle([x0, y0, x1, y0 + 0.1 * S], radius=0.04 * S, fill=color + (255,))
        d.rectangle([x0, y0 + 0.06 * S, x1, y0 + 0.1 * S], fill=color + (255,))
        for x in (x0 + 0.09 * S, x1 - 0.09 * S):
            d.rounded_rectangle([x - 0.015 * S, y0 - 0.04 * S, x + 0.015 * S, y0 + 0.03 * S], radius=0.01 * S,
                                fill=INK + (255,))
        text(img, label, 100, INK, dy=0.065, shadow=False)
    return draw


def g_duel(img):
    ball(img, -0.11, 0.0, 0.11, RED)
    ball(img, 0.11, 0.0, 0.11, BLUE)
    text(img, "VS", 64, GOLD, dy=0.0)
    star(img, 0, -0.2, 0.05, GOLD)


def g_graduate(img):
    glow_disc(img, GOLD, S * 0.22, 90)
    for i, (x, y, r) in enumerate(((-0.14, 0.06, 0.08), (0.0, -0.04, 0.11), (0.14, 0.06, 0.08))):
        star(img, x, y, r, GOLD)
    text(img, "30", 60, WHITE, dy=0.2)


def g_level10(img):
    pts = [(0, -0.22), (0.17, -0.15), (0.15, 0.08), (0, 0.22), (-0.15, 0.08), (-0.17, -0.15)]
    poly(img, pts, BLUE, outline=CYAN, width=0.014)
    text(img, "10", 120, WHITE)


def g_infinity(img):
    glow_disc(img, CYAN, S * 0.2, 90)
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(200):
        t = i / 199 * 2 * math.pi
        x = 0.2 * math.cos(t) / (1 + math.sin(t) ** 2)
        y = 0.2 * math.sin(t) * math.cos(t) / (1 + math.sin(t) ** 2)
        pts.append((C + x * S, C + y * S))
    d.line(pts, fill=CYAN + (255,), width=round(0.045 * S), joint="curve")
    ball(img, 0.0, 0.0, 0.035, YELLOW)


def g_stopwatch(img):
    glow_disc(img, ORANGE, S * 0.2, 100)
    circle(img, 0, 0.03, 0.18, fill=WHITE, outline=ORANGE, width=0.03)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([C - 0.04 * S, C - 0.23 * S, C + 0.04 * S, C - 0.17 * S], radius=0.015 * S, fill=ORANGE + (255,))
    d.line([(C, C + 0.03 * S), (C + 0.09 * S, C - 0.06 * S)], fill=INK + (255,), width=round(0.025 * S))
    text(img, "60", 54, INK, dy=0.1, shadow=False)


def g_stars(img):
    glow_disc(img, GOLD, S * 0.22, 110)
    star(img, 0, 0, 0.21, GOLD)


ACHIEVEMENTS = [  # (file / local id, Play Games name, glyph)
    ("first_lock", "First Lock", g_first_lock),
    ("score_50", "Getting Warm", g_score("50", GREEN)),
    ("score_250", "On Fire", g_score("250", ORANGE)),
    ("score_1000", "Hue Master", g_score("1000", GOLD, crown=True)),
    ("streak_10", "Sharpshooter", g_streak("10")),
    ("streak_25", "Laser Focus", g_streak("25")),
    ("fever_1", "Feverish", g_fever),
    ("combo_5", "Combo King", g_combo),
    ("boss_1", "Memory Lane", g_boss(None)),
    ("boss_10", "Elephant Brain", g_boss("10")),
    ("stage_3", "Explorer", g_stage3),
    ("stage_6", "Into the Void", g_void),
    ("not_50", "Contrarian", g_not),
    ("greedy_25", "Greedy", g_greedy),
    ("runs_100", "Just One More", g_runs),
    ("daily_7", "Regular", g_calendar("7", RED)),
    ("duel_win", "Rival", g_duel),
    ("levels_all", "Graduate", g_graduate),
    ("level_10", "Seasoned", g_level10),
]

LEADERBOARDS = [
    ("endless", "Endless", g_infinity),
    ("daily", "Daily Challenge", g_calendar("D", BLUE)),
    ("rush", "Rush", g_stopwatch),
    ("stars", "Level Stars", g_stars),
]

ACCENTS = [RED, YELLOW, BLUE, GREEN, ORANGE, PURPLE]


def render(glyph, accent):
    img = background(accent)
    ring(img)
    glyph(img)
    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main():
    rows = []
    for kind, items in (("achievements", ACHIEVEMENTS), ("leaderboards", LEADERBOARDS)):
        os.makedirs(os.path.join(OUT, kind), exist_ok=True)
        for i, (key, name, glyph) in enumerate(items):
            path = os.path.join(OUT, kind, f"{key}.png")
            render(glyph, ACCENTS[i % len(ACCENTS)]).save(path, optimize=True)
            rows.append((kind, key, name))
            print("wrote", os.path.relpath(path, ROOT))
    return rows


if __name__ == "__main__":
    main()
