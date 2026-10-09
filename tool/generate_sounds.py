#!/usr/bin/env python3
"""Generates the placeholder sound effects in assets/audio/.

Everything is synthesized so the MVP has no licensing questions. Replace the
files with designed sounds later; keep the names.

    python3 tool/generate_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def write(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = gain / peak
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767))
                for s in samples
            )
        )
    print("wrote", os.path.normpath(path))


def env(i, n, attack=0.002, decay=8.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-decay * t)


def fade_tail(samples, ms=8):
    n = int(RATE * ms / 1000)
    for k in range(min(n, len(samples))):
        samples[-1 - k] *= k / n
    return samples


def lock_click():
    """Crisp 'lock' click: noise transient + short low thump + metallic tick."""
    n = int(RATE * 0.12)
    rnd = random.Random(1)
    out = []
    for i in range(n):
        t = i / RATE
        noise = (rnd.random() * 2 - 1) * math.exp(-t * 180)
        thump = math.sin(2 * math.pi * (190 - 400 * t) * t) * math.exp(-t * 35)
        tick = math.sin(2 * math.pi * 2400 * t) * math.exp(-t * 90)
        out.append(0.5 * noise + 0.8 * thump + 0.35 * tick)
    return fade_tail(out)


def chime(freq, length=0.38):
    """Bright bell for Perfect hits."""
    n = int(RATE * length)
    out = []
    for i in range(n):
        t = i / RATE
        e = env(i, n, attack=0.002, decay=7.5)
        s = (
            math.sin(2 * math.pi * freq * t)
            + 0.45 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-t * 6)
            + 0.2 * math.sin(2 * math.pi * freq * 3.01 * t) * math.exp(-t * 12)
        )
        click = math.sin(2 * math.pi * 3200 * t) * math.exp(-t * 120)
        out.append(e * s + 0.25 * click)
    return fade_tail(out)


def fail():
    """Short, soft descending 'bwomp'."""
    n = int(RATE * 0.42)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 260 * math.exp(-t * 2.6)
        phase += 2 * math.pi * f / RATE
        s = math.sin(phase) + 0.3 * math.sin(phase * 2) + 0.12 * math.sin(phase * 3)
        out.append(s * env(i, n, attack=0.004, decay=5.0))
    return fade_tail(out)


def two_tone(f1, f2, step=0.07, length=0.22):
    n = int(RATE * length)
    out = []
    for i in range(n):
        t = i / RATE
        f = f1 if t < step else f2
        tt = t if t < step else t - step
        out.append(
            (math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t))
            * math.exp(-tt * 14)
            * min(1, t / 0.002)
        )
    return fade_tail(out)


def arpeggio(freqs, step=0.08, tail=0.35):
    n = int(RATE * (step * len(freqs) + tail))
    out = [0.0] * n
    for k, f in enumerate(freqs):
        start = int(RATE * step * k)
        for i in range(start, n):
            t = (i - start) / RATE
            out[i] += (
                math.sin(2 * math.pi * f * t) + 0.35 * math.sin(4 * math.pi * f * t)
            ) * math.exp(-t * 7) * min(1, t / 0.002)
    return fade_tail(out)


def ui_tick():
    n = int(RATE * 0.045)
    return fade_tail(
        [math.sin(2 * math.pi * 1500 * (i / RATE)) * math.exp(-(i / RATE) * 110) for i in range(n)]
    )


def sweep(f0, f1, length, gain_decay=4.0):
    """Rising/falling sine sweep with a soft second harmonic."""
    n = int(RATE * length)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / length)
        phase += 2 * math.pi * f / RATE
        out.append((math.sin(phase) + 0.3 * math.sin(2 * phase)) * math.exp(-t * gain_decay) * min(1, t / 0.004))
    return fade_tail(out)


def clang():
    """Metallic hit for the shield breaking."""
    n = int(RATE * 0.5)
    partials = [(523, 1.0), (1371, 0.6), (2083, 0.45), (2797, 0.3)]
    return fade_tail([
        sum(a * math.sin(2 * math.pi * f * (i / RATE)) for f, a in partials)
        * math.exp(-(i / RATE) * 7) * min(1, (i / RATE) / 0.002)
        for i in range(n)
    ])


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] if i < len(p) else 0 for p in parts) for i in range(n)]


def main():
    os.makedirs(OUT, exist_ok=True)
    write("hit.wav", lock_click())
    # Rising major-pentatonic steps for consecutive Perfects.
    steps = [0, 2, 4, 7, 9, 12, 14, 16]
    for k, st in enumerate(steps):
        write(f"perfect_{k}.wav", chime(880 * 2 ** (st / 12)), gain=0.8)
    write("fail.wav", fail(), gain=0.7)
    write("coin.wav", two_tone(1318.5, 1975.5), gain=0.6)
    write("new_best.wav", arpeggio([523.25, 659.25, 783.99, 1046.5]), gain=0.7)
    write("ui.wav", ui_tick(), gain=0.5)
    write("fever.wav", mix(sweep(300, 1800, 0.55, 2.5), arpeggio([880, 1108.7, 1318.5, 1760], step=0.06, tail=0.25)), gain=0.75)
    write("power_up.wav", arpeggio([1046.5, 1318.5, 1568, 2093], step=0.045, tail=0.2), gain=0.6)
    write("shield.wav", clang(), gain=0.7)
    write("stage.wav", arpeggio([392, 523.25, 659.25, 783.99, 1046.5], step=0.09, tail=0.5), gain=0.7)
    write("boss.wav", mix(sweep(220, 110, 0.9, 2.0), sweep(233, 116, 0.9, 2.0)), gain=0.7)


if __name__ == "__main__":
    main()
