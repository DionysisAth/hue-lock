#!/usr/bin/env python3
"""Edits the recorded gameplay into a 1920x1080 promo video (YouTube / Play
Store), with captions, the game's music and its sound effects.

    flutter test tool/promo_video_test.dart   # records build/promo/frames
    python3 tool/make_promo_video.py          # -> build/promo/hue-lock-promo.mp4

Needs Pillow, numpy and ffmpeg.
"""
import json
import math
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REC = os.path.join(ROOT, "build", "promo")
OUT = os.path.join(REC, "hue-lock-promo.mp4")
AUDIO = os.path.join(ROOT, "assets", "audio")
ICON = os.path.join(ROOT, "docs", "store", "icon-512.png")

W, H, FPS = 1920, 1080, 30
RED, BLUE, YELLOW, GREEN = (255, 61, 110), (47, 139, 255), (255, 201, 40), (34, 213, 139)
WHITE, SUB = (255, 255, 255), (170, 172, 210)

# Scene -> (playback speed, caption, sub caption).
SCENES = {
    "home": (1.0, "ONE TAP.", "PURE TIMING."),
    "streak": (1.35, "CHAIN PERFECTS", "and set off FEVER"),
    "boss": (2.0, "BEAT THE BOSS", "remember the colors"),
    "perks": (1.0, "PICK A PERK", "every run plays differently"),
    "hold": (1.0, "HOLD, LET GO", "and slow down time"),
    "not": (1.0, "RULES FLIP", "hit any color but this one"),
    "levels": (1.0, "30 LEVELS", "plus Rush, Daily, Zen and Duels"),
    "best": (1.2, "BEAT YOUR BEST", "and climb the weekly leaderboards"),
}
END_SECONDS = 4.0
# Longest a scene may run, in recorded frames (trims the tail).
MAX_FRAMES = {"not": 46}


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


def background():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.clip(np.sqrt(((x - W * 0.62) / W) ** 2 + ((y - H * 0.5) / H) ** 2) / 0.75, 0, 1)[..., None]
    inner = np.array((0x2E, 0x26, 0x5C), np.float32)
    outer = np.array((0x08, 0x08, 0x14), np.float32)
    img = Image.fromarray((inner + (outer - inner) * d ** 1.2).astype(np.uint8), "RGB").convert("RGBA")
    # A big soft four-color ring behind the phone.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    cx, cy, r = W * 0.66, H * 0.5, 470
    for i, c in enumerate((RED, YELLOW, BLUE, GREEN)):
        g.arc([cx - r, cy - r, cx + r, cy + r], -135 + i * 90 + 3, -45 + i * 90 - 3, fill=c + (70,), width=38)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(22)))
    return img


def gradient_text(text, size, stops):
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
    shadow = Image.new("RGBA", (w, h), (5, 5, 12, 255))
    out.paste(shadow, (0, 6), mask)
    out.paste(grad, (0, 0), mask)
    return out


def text_img(text, size, color):
    f = font(size)
    box = f.getbbox(text)
    img = Image.new("RGBA", (box[2] - box[0] + 8, box[3] - box[1] + 8), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((-box[0] + 4, -box[1] + 4), text, font=f, fill=color + (255,))
    return img


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    rec = json.load(open(os.path.join(REC, "events.json")))
    total = rec["frames"]
    marks = rec["scenes"] + [{"id": None, "frame": total}]

    # Which recorded frame each output frame shows, scene by scene.
    plan = []  # (source frame, scene id, progress 0..1 within the scene)
    starts = {}
    for a, b in zip(marks, marks[1:]):
        speed = SCENES[a["id"]][0]
        n = min(b["frame"] - a["frame"], MAX_FRAMES.get(a["id"], 10 ** 9))
        count = max(1, round(n / speed))
        starts[a["id"]] = len(plan)
        for i in range(count):
            plan.append((a["frame"] + min(n - 1, int(i * speed)), a["id"], i / count))
    end_frames = int(END_SECONDS * FPS)
    n_out = len(plan) + end_frames

    bg = background()
    logo = gradient_text("HUE LOCK", 92, [RED, BLUE, YELLOW, GREEN])
    caps = {k: (text_img(v[1], 84, WHITE), text_img(v[2], 40, SUB)) for k, v in SCENES.items()}
    phone_h = 980
    phone_w = round(phone_h / 2)
    px, py = round(W * 0.66 - phone_w / 2), (H - phone_h) // 2
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px - 6, py - 6, px + phone_w + 6, py + phone_h + 6], radius=46,
                                             fill=(0, 0, 0, 200))
    shadow = shadow.filter(ImageFilter.GaussianBlur(20))
    base = bg.copy()
    base.alpha_composite(shadow)
    ImageDraw.Draw(base).rounded_rectangle([px - 8, py - 8, px + phone_w + 8, py + phone_h + 8], radius=48,
                                           fill=(18, 18, 30, 255), outline=(70, 72, 110, 255), width=3)
    lx = 150

    # End card.
    icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
    icon = rounded(icon, 66)
    end = bg.copy()
    end.alpha_composite(icon, (W // 2 - 150, 170))
    big = gradient_text("HUE LOCK", 130, [RED, BLUE, YELLOW, GREEN])
    end.alpha_composite(big, (W // 2 - big.size[0] // 2, 500))
    t1 = text_img("ONE TAP. PURE TIMING.", 46, WHITE)
    end.alpha_composite(t1, (W // 2 - t1.size[0] // 2, 680))
    t2 = text_img("FREE ON GOOGLE PLAY", 40, YELLOW)
    end.alpha_composite(t2, (W // 2 - t2.size[0] // 2, 790))

    video_only = os.path.join(REC, "video.mp4")
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
         "-pix_fmt", "yuv420p", video_only],
        stdin=subprocess.PIPE)
    cache = {}
    for i in range(n_out):
        if i < len(plan):
            src, sid, k = plan[i]
            frame = base.copy()
            if src not in cache:
                cache.clear()
                g = Image.open(os.path.join(REC, "frames", f"{src:05d}.png")).convert("RGBA")
                cache[src] = rounded(g.resize((phone_w, phone_h), Image.LANCZOS), 40)
            frame.alpha_composite(cache[src], (px, py))
            frame.alpha_composite(logo, (lx, 110))
            # Caption: slides in at the start of its scene, fades out at the end.
            j = i - starts[sid]
            a_in = min(1.0, j / 8)
            ease = 1 - (1 - a_in) ** 3
            title, sub = caps[sid]
            for img, y in ((title, 430), (sub, 545)):
                layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
                layer = Image.blend(layer, img, ease)
                frame.alpha_composite(layer, (lx - round((1 - ease) * 40), y))
        else:
            j = i - len(plan)
            frame = end.copy()
            fade = min(1.0, j / 10)
            if fade < 1:
                frame = Image.blend(base, frame, fade)
        enc.stdin.write(frame.convert("RGB").tobytes())
    enc.stdin.close()
    enc.wait()

    # Sound: the game's music (looped, faded) plus its sound effects.
    duration = n_out / FPS
    srcs = [p[0] for p in plan]

    def out_frame(f):
        # First output frame showing this recorded frame or the next one kept.
        return next((i for i, s in enumerate(srcs) if s >= f), None)

    sfx = [(out_frame(e["frame"]) / FPS, e["sfx"]) for e in rec["events"]
           if out_frame(e["frame"]) is not None]
    inputs = ["-stream_loop", "-1", "-i", os.path.join(AUDIO, "music_3.wav")]
    filters = [f"[1:a]atrim=0:{duration:.2f},volume=0.55,afade=t=in:d=1,"
               f"afade=t=out:st={duration - 2:.2f}:d=2[m]"]
    labels = ["[m]"]
    for k, (t, name) in enumerate(sfx):
        inputs += ["-i", os.path.join(AUDIO, f"{name}.wav")]
        ms = round(t * 1000)
        filters.append(f"[{k + 2}:a]volume=0.9,adelay={ms}|{ms}[s{k}]")
        labels.append(f"[s{k}]")
    filters.append("".join(labels) + f"amix=inputs={len(labels)}:normalize=0,alimiter=limit=0.8:level=0[a]")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", video_only] + inputs +
        ["-filter_complex", ";".join(filters), "-map", "0:v", "-map", "[a]", "-c:v", "copy",
         "-c:a", "aac", "-b:a", "192k", "-t", f"{duration:.2f}", "-movflags", "+faststart", OUT],
        check=True)
    os.remove(video_only)
    print(f"wrote {os.path.relpath(OUT, ROOT)} ({duration:.1f} s, {len(sfx)} sounds)")


if __name__ == "__main__":
    main()
