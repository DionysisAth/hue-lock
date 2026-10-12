#!/usr/bin/env python3
"""Draws the Hue Lock app icon and writes every size the stores need.

The icon is the game itself: a dark ring with four colored zones, the white
pointer locked on the yellow zone and a yellow ball in the middle.

    python3 tool/generate_icon.py

Writes:
  android/app/src/main/res/mipmap-*/ic_launcher*.png   (legacy + adaptive)
  android/app/src/main/res/drawable*/splash_logo.png   (pre-Android 12 splash)
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png  (no alpha, as Apple wants)
  ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png
  docs/store/icon-512.png, docs/store/feature-graphic.png
Needs Pillow.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_TOP = (0x1A, 0x1B, 0x33)
BG_GLOW = (0x2E, 0x26, 0x5C)
BG_BOTTOM = (0x0B, 0x0C, 0x18)
TRACK = (0x35, 0x38, 0x57)
RED = (0xFF, 0x3D, 0x6E)
BLUE = (0x2F, 0x8B, 0xFF)
YELLOW = (0xFF, 0xC9, 0x28)
GREEN = (0x22, 0xD5, 0x8B)
WHITE = (255, 255, 255)

SS = 4  # supersampling for smooth edges

# Zones: (center angle in degrees, clockwise from 12 o'clock; width; color).
ZONES = [(-45, 86, RED), (45, 86, YELLOW), (135, 86, BLUE), (225, 86, GREEN)]
POINTER = 45  # locked on the yellow zone


def _gradient(size):
    """Background: a deep indigo glow behind the ring fading to near black."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / max(1, size - 1)
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.46) ** 2) / 0.72
    k = np.clip(d, 0, 1)[..., None] ** 1.2
    inner = np.array(BG_GLOW, np.float32)
    outer = np.array(BG_BOTTOM, np.float32)
    rgb = inner + (outer - inner) * k
    return Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")


def _arc_box(c, r):
    return [c - r, c - r, c + r, c + r]


def _pil_angle(deg):
    # PIL measures from 3 o'clock, clockwise; ours from 12 o'clock.
    return deg - 90


def _mix(a, b, k):
    return tuple(round(x + (y - x) * k) for x, y in zip(a, b))


def _sphere(S, c, r, color):
    """A glossy ball lit from the top left (RGBA layer of size S)."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    lx, ly = c - r * 0.38, c - r * 0.42
    d = np.sqrt((x - lx) ** 2 + (y - ly) ** 2) / (r * 1.55)
    d = np.clip(d, 0, 1)[..., None]
    light = np.array(_mix(color, WHITE, 0.55), np.float32)
    mid = np.array(color, np.float32)
    dark = np.array(_mix(color, (150, 60, 0), 0.38), np.float32)
    rgb = np.where(d < 0.45, light + (mid - light) * (d / 0.45),
                   mid + (dark - mid) * ((d - 0.45) / 0.55))
    inside = (np.sqrt((x - c) ** 2 + (y - c) ** 2) <= r).astype(np.float32)
    a = (inside * 255)[..., None]
    return Image.fromarray(np.concatenate([rgb, a], -1).astype(np.uint8), "RGBA")


def _blur(img, radius):
    return img.filter(ImageFilter.GaussianBlur(radius))


def _art(size, scale=1.0, mono=False):
    """The ring, zones, pointer and ball on a transparent square.

    [scale] shrinks the art around the center (adaptive icons need the
    content inside the middle two thirds).
    """
    S = size * SS
    c = S / 2
    r = S * 0.335 * scale  # ring radius (track center line)
    w = S * 0.105 * scale  # ring width
    ball = S * 0.165 * scale
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = math.radians(POINTER)
    ux, uy = math.sin(a), -math.cos(a)

    def ring_arc(draw, radius, width, fill, center, span):
        draw.arc(_arc_box(c, radius), _pil_angle(center - span / 2),
                 _pil_angle(center + span / 2), fill=fill, width=max(1, round(width)))

    if mono:
        d = ImageDraw.Draw(layer)
        for center, span, _ in ZONES:
            ring_arc(d, r + w / 2, w, (255, 255, 255, 255), center, span)
        d.ellipse(_arc_box(c, ball), fill=(255, 255, 255, 255))
    else:
        # Glow under the ring and the ball, brightest where the pointer locks.
        for center, span, color in ZONES:
            glow = Image.new("RGBA", (S, S), color + (0,))
            ring_arc(ImageDraw.Draw(glow), r + w * 0.95, w * 1.9, color + (120,), center, span)
            layer = Image.alpha_composite(layer, _blur(glow, S * 0.028))
        glow = Image.new("RGBA", (S, S), YELLOW + (0,))
        ImageDraw.Draw(glow).ellipse(_arc_box(c, ball * 1.4), fill=YELLOW + (90,))
        layer = Image.alpha_composite(layer, _blur(glow, S * 0.03))
        lx, ly = c + ux * r, c + uy * r
        glow = Image.new("RGBA", (S, S), (255, 226, 120, 0))
        ImageDraw.Draw(glow).ellipse([lx - w * 0.9, ly - w * 0.9, lx + w * 0.9, ly + w * 0.9], fill=(255, 226, 120, 150))
        layer = Image.alpha_composite(layer, _blur(glow, w * 0.45))

        # Ball shadow, then the glossy ball.
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse(_arc_box(c, ball * 1.08), fill=(0, 0, 0, 150))
        sh = _blur(sh, ball * 0.18)
        layer = Image.alpha_composite(layer, ImageChops_offset(sh, 0, round(ball * 0.14)))
        layer = Image.alpha_composite(layer, _sphere(S, c, ball, YELLOW))

        d = ImageDraw.Draw(layer)
        # Zones: tube shading (base, dark inner band, light outer band).
        for center, span, color in ZONES:
            ring_arc(d, r + w / 2, w, color + (255,), center, span)
            ring_arc(d, r - w * 0.2, w * 0.3, _mix(color, (0, 0, 0), 0.18) + (255,), center, span)
            ring_arc(d, r + w * 0.4, w * 0.16, _mix(color, WHITE, 0.4) + (255,), center, span - 5)

        # Ball details: bounce light, soft and sharp highlights, rim.
        hl = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        h = ImageDraw.Draw(hl)
        h.arc(_arc_box(c, ball * 0.84), 10, 100, fill=_mix(YELLOW, WHITE, 0.5) + (90,), width=round(ball * 0.12))
        hx, hy = c - ball * 0.3, c - ball * 0.4
        h.ellipse([hx - ball * 0.36, hy - ball * 0.22, hx + ball * 0.36, hy + ball * 0.22], fill=(255, 255, 255, 170))
        layer = Image.alpha_composite(layer, _blur(hl, ball * 0.05))
        d = ImageDraw.Draw(layer)
        sx, sy = c - ball * 0.4, c - ball * 0.46
        d.ellipse([sx - ball * 0.11, sy - ball * 0.11, sx + ball * 0.11, sy + ball * 0.11], fill=(255, 255, 255, 255))

    # Pointer: an outlined needle across the ring with an arrowhead outside.
    d = ImageDraw.Draw(layer)
    inner, outer = r - w * 0.85, r + w * 0.85
    p0 = (c + ux * inner, c + uy * inner)
    p1 = (c + ux * outer, c + uy * outer)
    pw = w * 0.32
    side = (-uy, ux)
    tip = (c + ux * (r + w * 1.0), c + uy * (r + w * 1.0))
    back = (c + ux * (r + w * 1.55), c + uy * (r + w * 1.55))
    head = [tip, (back[0] + side[0] * pw * 1.05, back[1] + side[1] * pw * 1.05),
            (back[0] - side[0] * pw * 1.05, back[1] - side[1] * pw * 1.05)]

    def needle(width, fill):
        d.line([p0, p1], fill=fill, width=round(width))
        for p in (p0, p1):
            d.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=fill)

    if mono:
        needle(pw * 2.4, (0, 0, 0, 0))  # cut a gap so it reads in one color
        needle(pw, (255, 255, 255, 255))
        d.polygon(head, fill=(255, 255, 255, 255))
    else:
        needle(pw + S * 0.012, (10, 10, 20, 170))
        d.polygon(head, fill=(10, 10, 20, 150), outline=(10, 10, 20, 150), width=round(S * 0.008))
        needle(pw, WHITE + (255,))
        d.polygon(head, fill=WHITE + (255,))

    return layer.resize((size, size), Image.LANCZOS)


def ImageChops_offset(img, dx, dy):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (dx, dy))
    return out


def full_icon(size, shape="square"):
    """Background + art. shape: square (iOS / store), rounded, circle."""
    S = size * SS
    img = _gradient(S)
    img = img.resize((size, size), Image.LANCZOS)
    img = Image.alpha_composite(img, _art(size))
    if shape == "square":
        return img
    mask = Image.new("L", (S, S), 0)
    m = ImageDraw.Draw(mask)
    if shape == "circle":
        m.ellipse([0, 0, S - 1, S - 1], fill=255)
    else:
        m.rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.22, fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def save(img, *parts, rgb=False):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (img.convert("RGB") if rgb else img).save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def android():
    res = ("android", "app", "src", "main", "res")
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in densities.items():
        legacy = round(48 * k)
        save(full_icon(legacy, "rounded"), *res, f"mipmap-{name}", "ic_launcher.png")
        save(full_icon(legacy, "circle"), *res, f"mipmap-{name}", "ic_launcher_round.png")
        # Adaptive layers are 108dp; the visible part is the middle 72dp.
        adaptive = round(108 * k)
        save(_art(adaptive, scale=0.78), *res, f"mipmap-{name}", "ic_launcher_foreground.png")
        save(
            _gradient(adaptive * SS).resize((adaptive, adaptive), Image.LANCZOS),
            *res, f"mipmap-{name}", "ic_launcher_background.png",
        )
        save(_art(adaptive, scale=0.78, mono=True), *res, f"mipmap-{name}", "ic_launcher_monochrome.png")
        # Pre-Android 12 splash: the logo, 160dp.
        save(_art(round(160 * k)), *res, f"drawable-{name}", "splash_logo.png")


def ios():
    base = ("ios", "Runner", "Assets.xcassets")
    sizes = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in sizes.items():
        # Apple rejects icons with an alpha channel; it rounds them itself.
        save(full_icon(px), *base, "AppIcon.appiconset", name, rgb=True)
    for name, k in (("LaunchImage.png", 1), ("LaunchImage@2x.png", 2), ("LaunchImage@3x.png", 3)):
        save(_art(round(160 * k)), *base, "LaunchImage.imageset", name)


def _font(size):
    for path in (
        "/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf",
        os.path.expanduser("~/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf"),
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def store():
    save(full_icon(512), "docs", "store", "icon-512.png", rgb=True)
    # Feature graphic: 1024x500, icon art on the left, name on the right.
    W, H = 1024, 500
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        k = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * k) for a, b in zip(BG_TOP, BG_BOTTOM)))
    bg = bg.convert("RGBA")
    art = _art(460)
    bg.alpha_composite(art, (40, 20))
    d = ImageDraw.Draw(bg)
    title = _font(112)
    tag = _font(36)
    # Title in the in-game logo's rainbow gradient, with a dark extrusion.
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.text((520, 150), "HUE", font=title, fill=255)
    md.text((520, 262), "LOCK", font=title, fill=255)
    shadow = Image.new("RGBA", (W, H), (5, 5, 12, 255))
    bg.paste(shadow, (0, 7), mask)
    stops = [RED, BLUE, YELLOW, GREEN]
    grad = Image.new("RGB", (W, H))
    gd = ImageDraw.Draw(grad)
    for x in range(W):
        t = min(max((x - 520) / 440, 0), 1) * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        gd.line([(x, 0), (x, H)], fill=_mix(stops[i], stops[i + 1], t - i))
    bg.paste(grad.convert("RGBA"), (0, 0), mask)
    d = ImageDraw.Draw(bg)
    x = 524
    for word, color in (("TAP", RED), ("ON", BLUE), ("ITS", YELLOW), ("COLOR", GREEN)):
        d.text((x, 395), word, font=tag, fill=color)
        x += d.textlength(word + " ", font=tag)
    save(bg, "docs", "store", "feature-graphic.png", rgb=True)


if __name__ == "__main__":
    what = sys.argv[1:] or ["android", "ios", "store"]
    for w in what:
        {"android": android, "ios": ios, "store": store}[w]()
