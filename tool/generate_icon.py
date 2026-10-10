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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_TOP = (0x1A, 0x1B, 0x33)
BG_BOTTOM = (0x0B, 0x0C, 0x18)
TRACK = (0x35, 0x38, 0x57)
RED = (0xFF, 0x3D, 0x6E)
BLUE = (0x2F, 0x8B, 0xFF)
YELLOW = (0xFF, 0xC9, 0x28)
GREEN = (0x22, 0xD5, 0x8B)
WHITE = (255, 255, 255)

SS = 4  # supersampling for smooth edges

# Zones: (center angle in degrees, clockwise from 12 o'clock; width; color).
ZONES = [(-50, 62, RED), (40, 62, YELLOW), (140, 56, BLUE), (225, 56, GREEN)]
POINTER = 40  # locked on the yellow zone


def _gradient(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        k = y / max(1, size - 1)
        c = tuple(round(a + (b - a) * k) for a, b in zip(BG_TOP, BG_BOTTOM))
        d.line([(0, y), (size, y)], fill=c)
    return img.convert("RGBA")


def _arc_box(c, r):
    return [c - r, c - r, c + r, c + r]


def _pil_angle(deg):
    # PIL measures from 3 o'clock, clockwise; ours from 12 o'clock.
    return deg - 90


def _art(size, scale=1.0, mono=False):
    """The ring, zones, pointer and ball on a transparent square.

    [scale] shrinks the art around the center (adaptive icons need the
    content inside the middle two thirds).
    """
    S = size * SS
    c = S / 2
    r = S * 0.33 * scale  # ring radius (track center line)
    w = S * 0.075 * scale  # ring width
    ball = S * 0.155 * scale
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    def col(rgb, a=255):
        return (255, 255, 255, a) if mono else rgb + (a,)

    if not mono:
        # Soft glow under the zones and the ball.
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        g = ImageDraw.Draw(glow)
        for center, width, color in ZONES:
            g.arc(
                _arc_box(c, r + w * 0.8),
                _pil_angle(center - width / 2),
                _pil_angle(center + width / 2),
                fill=color + (120,),
                width=round(w * 1.6),
            )
        g.ellipse(_arc_box(c, ball * 1.3), fill=YELLOW + (90,))
        glow = glow.filter(ImageFilter.GaussianBlur(S * 0.022))
        layer = Image.alpha_composite(layer, glow)

    d = ImageDraw.Draw(layer)
    if not mono:
        d.ellipse(_arc_box(c, r + w / 2), outline=TRACK + (255,), width=round(w))
    for center, width, color in ZONES:
        d.arc(
            _arc_box(c, r + w / 2),
            _pil_angle(center - width / 2),
            _pil_angle(center + width / 2),
            fill=col(color),
            width=round(w),
        )
    # Ball with a highlight.
    if mono:
        d.ellipse(_arc_box(c, ball), fill=col(WHITE))
    else:
        d.ellipse(_arc_box(c, ball), fill=YELLOW + (255,))
        hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        h = ImageDraw.Draw(hl)
        hx, hy = c - ball * 0.32, c - ball * 0.36
        h.ellipse(
            [hx - ball * 0.36, hy - ball * 0.26, hx + ball * 0.36, hy + ball * 0.26],
            fill=(255, 255, 255, 120),
        )
        hl = hl.filter(ImageFilter.GaussianBlur(ball * 0.08))
        layer = Image.alpha_composite(layer, hl)
        d = ImageDraw.Draw(layer)

    # Pointer: a white bar across the ring at the yellow zone.
    a = math.radians(POINTER)
    ux, uy = math.sin(a), -math.cos(a)
    inner, outer = r - w * 0.95, r + w * 0.95
    p0 = (c + ux * inner, c + uy * inner)
    p1 = (c + ux * outer, c + uy * outer)
    pw = w * 0.3
    if not mono:
        pg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(pg).line([p0, p1], fill=(255, 255, 255, 170), width=round(pw * 2.4))
        pg = pg.filter(ImageFilter.GaussianBlur(S * 0.012))
        layer = Image.alpha_composite(layer, pg)
        d = ImageDraw.Draw(layer)
    if mono:
        # Cut a gap around the pointer so it reads in one color.
        d.line([p0, p1], fill=(0, 0, 0, 0), width=round(pw * 2.2))
    d.line([p0, p1], fill=col(WHITE), width=round(pw))
    for p in (p0, p1):
        d.ellipse([p[0] - pw / 2, p[1] - pw / 2, p[0] + pw / 2, p[1] + pw / 2], fill=col(WHITE))

    return layer.resize((size, size), Image.LANCZOS)


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
    d.text((520, 150), "HUE", font=title, fill=WHITE)
    d.text((520, 262), "LOCK", font=title, fill=WHITE)
    x = 524
    for word, color in (("TAP", RED), ("ON", BLUE), ("ITS", YELLOW), ("COLOR", GREEN)):
        d.text((x, 395), word, font=tag, fill=color)
        x += d.textlength(word + " ", font=tag)
    save(bg, "docs", "store", "feature-graphic.png", rgb=True)


if __name__ == "__main__":
    what = sys.argv[1:] or ["android", "ios", "store"]
    for w in what:
        {"android": android, "ios": ios, "store": store}[w]()
