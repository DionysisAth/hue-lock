#!/usr/bin/env python3
"""Generates the adaptive music loops in assets/audio/music_1..4.wav.

One 8-bar loop in A minor (Am - F - C - G) at 128 BPM, rendered at four
intensities that stack layers:
  1: pad + sub bass
  2: + kick and offbeat hats
  3: + driving bass, clap, shaker
  4: + 16th-note arpeggio (Fever)
All four have the same length and timing so the game can crossfade between
them in place. Everything is synthesized (no licensing questions).

    python3 tool/generate_music.py
"""

import os
import wave

import numpy as np

SR = 22050
BPM = 128
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 8
N = int(round(SR * BAR * BARS))
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# Am, F, C, G (MIDI root, chord tones).
CHORDS = [
    (45, [57, 60, 64]),
    (41, [57, 60, 65]),
    (48, [55, 60, 64]),
    (43, [55, 59, 62]),
] * 2


def add(buf, start_s, sig):
    """Adds sig at start_s, wrapping around so the loop is seamless."""
    i = int(round(start_s * SR)) % N
    n = len(sig)
    end = i + n
    if end <= N:
        buf[i:end] += sig
    else:
        first = N - i
        buf[i:] += sig[:first]
        rest = sig[first:]
        while len(rest):
            take = min(len(rest), N)
            buf[:take] += rest[:take]
            rest = rest[take:]


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env(dur, attack, release):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((dur - t) / max(release, 1e-4), 0, 1)
    return a * r


def tone(freq, dur, harmonics=(1.0,), decay=None, attack=0.005, release=0.05):
    t = t_axis(dur)
    sig = sum(a * np.sin(2 * np.pi * freq * (k + 1) * t) for k, a in enumerate(harmonics))
    e = env(dur, attack, release)
    if decay:
        e *= np.exp(-t / decay)
    return sig * e


def noise(dur, decay, hp=True):
    n = rng.uniform(-1, 1, int(dur * SR))
    if hp:  # crude high-pass: subtract a smoothed copy
        k = np.ones(8) / 8
        n = n - np.convolve(n, k, mode="same")
    return n * np.exp(-t_axis(dur) / decay)


def pad():
    buf = np.zeros(N)
    for bar, (_, tones) in enumerate(CHORDS):
        for m in tones:
            sig = tone(hz(m), BAR + 0.3, harmonics=(1, 0.35, 0.15, 0.06), attack=0.35, release=0.4)
            add(buf, bar * BAR, sig * 0.16)
    return buf


def sub():
    buf = np.zeros(N)
    for bar, (root, _) in enumerate(CHORDS):
        add(buf, bar * BAR, tone(hz(root), BAR, harmonics=(1, 0.2), attack=0.03, release=0.2) * 0.35)
    return buf


def kick():
    buf = np.zeros(N)
    dur = 0.32
    t = t_axis(dur)
    f = 45 + 110 * np.exp(-t / 0.04)
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)
    for b in range(BARS * 4):
        add(buf, b * BEAT, sig * 0.75)
    return buf


def hats():
    buf = np.zeros(N)
    sig = noise(0.05, 0.012)
    for b in range(BARS * 4):
        add(buf, b * BEAT + BEAT / 2, sig * 0.22)
    return buf


def bass():
    buf = np.zeros(N)
    for bar, (root, _) in enumerate(CHORDS):
        for e8 in range(8):
            m = root + (12 if e8 % 2 else 0)
            sig = tone(hz(m), BEAT / 2, harmonics=(1, 0.5, 0.33, 0.25, 0.2), decay=0.11, release=0.02)
            add(buf, bar * BAR + e8 * BEAT / 2, sig * 0.22)
    return buf


def clap():
    buf = np.zeros(N)
    sig = noise(0.16, 0.045)
    for b in range(BARS * 4):
        if b % 4 in (1, 3):
            add(buf, b * BEAT, sig * 0.35)
    return buf


def shaker():
    buf = np.zeros(N)
    sig = noise(0.03, 0.007)
    for s in range(BARS * 16):
        add(buf, s * BEAT / 4, sig * (0.10 if s % 2 else 0.06))
    return buf


def arp():
    buf = np.zeros(N)
    for bar, (_, tones) in enumerate(CHORDS):
        pattern = [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[1] + 24]
        for s in range(16):
            m = pattern[s % 4]
            sig = tone(hz(m), BEAT / 4 + 0.08, harmonics=(1, 0.45, 0.25, 0.12), decay=0.07, release=0.03)
            add(buf, bar * BAR + s * BEAT / 4, sig * 0.13)
    return buf


def write(name, samples, scale):
    data = np.clip(samples * scale, -1, 1)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    print("wrote", os.path.normpath(path))


def main():
    os.makedirs(OUT, exist_ok=True)
    layers = [
        pad() + sub(),
        kick() + hats(),
        bass() + clap() + shaker(),
        arp(),
    ]
    tracks = [sum(layers[: k + 1]) for k in range(4)]
    # One scale for all, so higher intensities are genuinely louder.
    scale = 0.85 / max(np.max(np.abs(t)) for t in tracks)
    for k, t in enumerate(tracks):
        write(f"music_{k + 1}.wav", t, scale)


if __name__ == "__main__":
    main()
