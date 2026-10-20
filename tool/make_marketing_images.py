#!/usr/bin/env python3
"""Builds the advertising image pack from the real in-game captures.

    flutter test tool/store_screenshots_test.dart   # raw captures
    python3 tool/frame_screenshots.py               # store screenshots
    python3 tool/make_marketing_images.py           # -> build/marketing/

Writes build/marketing/:
  in-game/          raw 1080x2160 gameplay captures, no text
  store-screenshots/ the framed Play Store screenshots
  square-1080/      1080x1080 posts (Instagram, Facebook, X)
  story-1080x1920/  1080x1920 stories / reels / TikTok covers
  landscape-1920/   1920x1080 banners (YouTube, X header, ads)
  brand/            app icon and feature graphic
Needs Pillow and numpy.
"""
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "build", "screenshots")
STORE = os.path.join(ROOT, "docs", "store")
OUT = os.path.join(ROOT, "build", "marketing")

RED, BLUE, YELLOW, GREEN = (255, 61, 110), (47, 139, 255), (255, 201, 40), (34, 213, 139)
WHITE, SUB = (255, 255, 255), (170, 172, 210)

SHOTS = [  # (capture, headline, line 2, accent)
    ("1_home", "ONE TAP.", "PURE TIMING.", YELLOW),
    ("2_perfect", "CHAIN PERFECTS", "INTO FEVER", RED),
    ("3_not", "RULES THAT", "FLIP ON YOU", BLUE),
    ("4_boss", "REMEMBER THE", "BOSS SEQUENCE", GREEN),
    ("5_levels", "30 LEVELS", "TO MASTER", YELLOW),
    ("6_game_over", "SO CLOSE.", "ONE MORE TRY?", RED),
    ("7_perks", "BEAT THE BOSS,", "PICK A PERK", GREEN),
    ("8_hold_focus", "HOLD ON,", "SLOW DOWN TIME", BLUE),
]


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


def background(w, h, accent, cx=0.5, cy=0.5):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.clip(np.sqrt(((x - w * cx) / max(w, h)) ** 2 + ((y - h * cy) / max(w, h)) ** 2) / 0.7, 0, 1)[..., None]
    inner = np.array(mix((0x2E, 0x26, 0x5C), accent, 0.25), np.float32)
    outer = np.array((0x08, 0x08, 0x14), np.float32)
    return Image.fromarray((inner + (outer - inner) * d ** 1.2).astype(np.uint8), "RGB").convert("RGBA")


def gradient_text(text, size, stops=(RED, BLUE, YELLOW, GREEN)):
    f = font(size)
    box = f.getbbox(text)
    w, h = box[2] - box[0] + 8, box[3] - box[1] + 16
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((-box[0] + 4, -box[1] + 4), text, font=f, fill=255)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    for x in range(w):
        t = x / max(1, w - 1) * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        gd.line([(x, 0), (x, h)], fill=mix(stops[i], stops[i + 1], t - i) + (255,))
    out = Image.new("RGBA", (w, h + 8), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), (5, 5, 12, 255)), (0, 6), mask)
    out.paste(grad, (0, 0), mask)
    return out


def text(img, xy, s, size, color, anchor="la"):
    ImageDraw.Draw(img).text(xy, s, font=font(size), fill=color + (255,), anchor=anchor)


def phone(shot, height):
    """The capture as a rounded phone screen with a soft shadow."""
    w = round(height / 2)
    screen = shot.resize((w, height), Image.LANCZOS).convert("RGBA")
    r = round(height * 0.045)
    mask = Image.new("L", (w, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, height - 1], radius=r, fill=255)
    pad = round(height * 0.06)
    out = Image.new("RGBA", (w + pad * 2, height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("L", out.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle([pad, pad + 8, pad + w, pad + height + 8], radius=r, fill=210)
    out.paste(Image.new("RGBA", out.size, (0, 0, 0, 255)), (0, 0), sh.filter(ImageFilter.GaussianBlur(pad / 3)))
    bezel = Image.new("L", out.size, 0)
    ImageDraw.Draw(bezel).rounded_rectangle([pad - 6, pad - 6, pad + w + 6, pad + height + 6], radius=r + 6,
                                            fill=255)
    out.paste(Image.new("RGBA", out.size, (24, 24, 38, 255)), (0, 0), bezel)
    out.paste(screen, (pad, pad), mask)
    return out, pad


def ring(img, cx, cy, r, width, alpha=70):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for i, c in enumerate((RED, YELLOW, BLUE, GREEN)):
        g.arc([cx - r, cy - r, cx + r, cy + r], -135 + i * 90 + 3, -45 + i * 90 - 3, fill=c + (alpha,), width=width)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(width * 0.6)))


def fit(s, size, width):
    """The largest font size up to [size] at which [s] fits in [width]."""
    while size > 20 and font(size).getlength(s) > width:
        size -= 2
    return size


def square(shot, title, line2, accent):
    img = background(1080, 1080, accent, 0.7, 0.5)
    ring(img, 790, 540, 430, 32)
    p, pad = phone(shot, 900)
    x = 1080 - p.size[0] + pad - 50
    img.alpha_composite(p, (x, 540 - p.size[1] // 2))
    room = x + pad - 60 - 40
    logo = gradient_text("HUE LOCK", 70)
    img.alpha_composite(logo, (60, 70))
    size = min(fit(title, 66, room), fit(line2, 66, room))
    text(img, (60, 430), title, size, WHITE)
    text(img, (60, 430 + round(size * 1.2)), line2, size, accent)
    text(img, (60, 950), "FREE ON GOOGLE PLAY", 32, SUB)
    return img


def story(shot, title, line2, accent):
    img = background(1080, 1920, accent, 0.5, 0.58)
    ring(img, 540, 1120, 520, 36)
    logo = gradient_text("HUE LOCK", 110)
    img.alpha_composite(logo, (540 - logo.size[0] // 2, 110))
    text(img, (540, 330), title, 76, WHITE, "ma")
    text(img, (540, 420), line2, 76, accent, "ma")
    p, pad = phone(shot, 1240)
    img.alpha_composite(p, (540 - p.size[0] // 2, 560 - pad))
    text(img, (540, 1850), "FREE ON GOOGLE PLAY", 40, SUB, "mb")
    return img


def landscape(shot, title, line2, accent):
    img = background(1920, 1080, accent, 0.66, 0.5)
    ring(img, 1270, 540, 480, 38)
    p, pad = phone(shot, 980)
    img.alpha_composite(p, (1270 - p.size[0] // 2, 540 - p.size[1] // 2))
    logo = gradient_text("HUE LOCK", 110)
    img.alpha_composite(logo, (120, 140))
    text(img, (120, 430), title, 90, WHITE)
    text(img, (120, 540), line2, 90, accent)
    text(img, (120, 900), "ONE TAP. PURE TIMING.  FREE ON GOOGLE PLAY", 36, SUB)
    return img


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    dirs = {k: os.path.join(OUT, k) for k in
            ("in-game", "store-screenshots", "square-1080", "story-1080x1920", "landscape-1920", "brand")}
    for d in dirs.values():
        os.makedirs(d)
    for name, title, line2, accent in SHOTS:
        shot = Image.open(os.path.join(RAW, f"{name}.png")).convert("RGB")
        shot.save(os.path.join(dirs["in-game"], f"{name}.png"), optimize=True)
        square(shot, title, line2, accent).convert("RGB").save(
            os.path.join(dirs["square-1080"], f"{name}.png"), optimize=True)
        story(shot, title, line2, accent).convert("RGB").save(
            os.path.join(dirs["story-1080x1920"], f"{name}.png"), optimize=True)
        landscape(shot, title, line2, accent).convert("RGB").save(
            os.path.join(dirs["landscape-1920"], f"{name}.png"), optimize=True)
        shutil.copy(os.path.join(STORE, "screenshots", f"{name}.png"), dirs["store-screenshots"])
    shutil.copy(os.path.join(STORE, "icon-512.png"), dirs["brand"])
    shutil.copy(os.path.join(STORE, "feature-graphic.png"), dirs["brand"])
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
