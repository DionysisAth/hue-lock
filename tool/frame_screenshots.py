#!/usr/bin/env python3
"""Adds a caption to each raw store screenshot.

    flutter test tool/store_screenshots_test.dart   # -> build/screenshots/
    python3 tool/frame_screenshots.py               # -> docs/store/screenshots/

Output is 1080x1920 (9:16), which both Google Play and the App Store accept
for phones. Needs Pillow.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

from generate_icon import BG_BOTTOM, BG_TOP, BLUE, GREEN, RED, YELLOW, _font

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "build", "screenshots")
OUT = os.path.join(ROOT, "docs", "store", "screenshots")

SHOTS = [
    ("1_home", "ONE TAP.", "PURE TIMING.", YELLOW),
    ("2_perfect", "CHAIN PERFECTS", "INTO FEVER", RED),
    ("3_not", "RULES THAT", "FLIP ON YOU", BLUE),
    ("4_boss", "REMEMBER THE", "BOSS SEQUENCE", GREEN),
    ("5_levels", "60 LEVELS", "TO MASTER", YELLOW),
    ("6_game_over", "SO CLOSE.", "ONE MORE TRY?", RED),
    ("7_perks", "BEAT THE BOSS,", "PICK A PERK", GREEN),
]

W, H = 1080, 1920


def frame(name, line1, line2, accent):
    canvas = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(canvas)
    for y in range(H):
        k = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * k) for a, b in zip(BG_TOP, BG_BOTTOM)))
    font = _font(84)
    for i, (text, color) in enumerate(((line1, (255, 255, 255)), (line2, accent))):
        tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, 70 + i * 100), text, font=font, fill=color)

    shot = Image.open(os.path.join(RAW, f"{name}.png")).convert("RGB")
    sh = H - 330
    sw = round(shot.width * sh / shot.height)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, 300
    radius = 44
    # Soft shadow, then the screenshot with rounded corners.
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 12, x + sw, y + sh + 12], radius, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas.paste((0, 0, 0), (0, 0), shadow)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius, fill=255)
    canvas.paste(shot, (x, y), mask)
    ImageDraw.Draw(canvas).rounded_rectangle(
        [x, y, x + sw - 1, y + sh - 1], radius, outline=(255, 255, 255, 40), width=2
    )
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.png")
    canvas.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    for shot in SHOTS:
        frame(*shot)
