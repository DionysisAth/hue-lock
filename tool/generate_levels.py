#!/usr/bin/env python3
"""Writes assets/config/levels.json: 10 chapters x 3 levels, an introduction
to every mechanic (Endless is the long game).

Difficulty rises evenly over the map (pointer speed, zone size and target
count follow the level's position), and a chapter's lesson level plays like
an earlier one. Edit the tables below and
re-run:

    python3 tool/generate_levels.py

Level fields are documented in the file's _comment and lib/meta/levels.dart.
"""
import json
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "config", "levels.json")

# (chapter title, unlock stars, reward, levels)
# Each level: (title, teaches, stage dict, extras dict, goals or None)
# goals None = the default "Perfects" + "in a row" pair for its size.
CHAPTERS = [
    ("The Basics", {"coins": 100}, [
        ("First Lock", "Tap when the pointer is on the zone that matches the ball. The fuse around the ball burns down: don't let the pointer pass the zone.",
         {"colors": [1, 1]}, {"targets": 8, "ease": 2}, ["perfects:2", "streak:2"]),
        ("Sweet Spot", "The bright band inside each zone is the Perfect window. Perfects are worth 3, and in a row they raise your combo.",
         {"colors": [1, 1]}, {"ease": 1}, ["perfects:4", "streak:3"]),
        ("Two Colors", "Now there are two colors. Only the one matching the ball counts.",
         {"colors": [2, 2]}, {}, ["perfects:5", "streak:4"]),
    ]),
    ("Focus", {"coins": 100}, [
        ("Slow Down", "Perfects fill the FOCUS button in the corner. Tap it to slow time while the meter lasts. Taps on it never count as a miss.",
         {"colors": [1, 2]}, {"ease": 2}, ["focus:1", "streak:3"]),
        ("Save It", "Focus runs out fast. Fill it again with Perfects and save it for the round that needs it.",
         {"colors": [2, 2]}, {"ease": 1}, ["focus:2", "perfects:5"]),
        ("Tiny Targets", "Small zones. Slow time to land them.",
         {"colors": [2, 3]}, {"sizeDelta": -8}, ["focus:2", "streak:4"]),
    ]),
    ("Turnaround", {"coins": 50, "ball": "bullseye"}, [
        ("About Face", "REVERSE: the pointer flips direction after every hit.",
         {"colors": [1, 1], "reverse": 1}, {"ease": 1}, ["perfects:4", "streak:4"]),
        ("Greedy", "GREEDY: a thin gold-rimmed zone is worth +5. Go for it, or wait for the safe one.",
         {"colors": [2, 2], "reverse": 0.5, "bonus": 0.8}, {}, ["greedy:1", "greedy:3"]),
        ("Lock Sets", "Clear the dots above the ball in a row for a set bonus. Power-ups ride on targets: shield, slow-mo and wide.",
         {"colors": [2, 3], "reverse": 1, "locks": [3, 4]}, {"powerUpChance": 0.4}, ["powerUps:1", "streak:4"]),
    ]),
    ("Hold On", {"coins": 120, "tokens": 1}, [
        ("Hold On", "HOLD: some targets are long, with a white mark at the end. Press when the pointer is in it, keep holding, and let go on the mark.",
         {"colors": [1, 1], "hold": 1}, {"ease": 2}, ["holds:3", "perfects:2"]),
        ("Let Go", "Letting go right on the white mark is a Perfect. Too soon is a miss.",
         {"colors": [1, 2], "hold": 1}, {"ease": 1}, ["holds:5", "perfects:4"]),
        ("Hold and Turn", "Taps and holds, with a pointer that flips. Read each target.",
         {"colors": [2, 3], "hold": 0.7, "reverse": 0.6}, {}, ["holds:3", "streak:4"]),
    ]),
    ("Opposites", {"coins": 150, "theme": "sunset"}, [
        ("Not That One", "NOT: the ball shows a crossed-out color. Hit any color EXCEPT that one.",
         {"colors": [3, 3], "inverted": 1}, {"ease": 1}, None),
        ("Decoys", "DECOYS: a wrong color sits right next to the right one. Tap a little early or late and you lose.",
         {"colors": [3, 4], "decoys": 1}, {}, ["perfects:6", "ratio:60"]),
        ("Mixed Signals", "NOT rounds, decoys and flips together. Read the ball first.",
         {"colors": [3, 4], "decoys": 1, "reverse": 0.6, "inverted": 0.4}, {}, None),
    ]),
    ("Spin Cycle", {"coins": 150, "tokens": 1}, [
        ("Carousel", "SPIN: the ring turns too, so zones move while the pointer moves.",
         {"colors": [2, 2], "rotate": 1}, {"ease": 1}, None),
        ("Ghosts", "GHOST: zones blink in and out. They always start visible: remember where they are.",
         {"colors": [2, 3], "ghost": 1}, {"ease": 1}, None),
        ("Haunted Carousel", "Spinning ghosts. Watch the ring, not just the pointer.",
         {"colors": [3, 4], "rotate": 0.8, "ghost": 0.7, "reverse": 0.5}, {}, None),
    ]),
    ("Split Second", {"coins": 50, "ball": "swirl"}, [
        ("Two at Once", "SPLIT: the ball is two colors. Hit the left one first, then the right one, in one lap.",
         {"colors": [2, 3], "split": 1}, {"ease": 1, "addTargets": -2}, None),
        ("Split Decision", "Splits that change direction. The second color is always after the first.",
         {"colors": [2, 4], "split": 0.7, "reverse": 1}, {}, None),
        ("Power Play", "Lots of power-ups. Collect a shield and keep it to the end.",
         {"colors": [2, 4], "split": 0.3, "inverted": 0.3, "decoys": 1}, {"powerUpChance": 0.4, "powerUpTypes": ["shield"]}, ["shield", "streak:6"]),
    ]),
    ("Fever Pitch", {"coins": 250, "tokens": 1}, [
        ("Fever Pitch", "5 Perfects in a row starts FEVER: double points and a faster pointer. A Good ends it.",
         {"colors": [1, 2]}, {"ease": 2}, ["fevers:1", "streak:6"]),
        ("Heat Wave", "Every Perfect during Fever scores double. Keep it going through flips.",
         {"colors": [2, 3], "reverse": 0.5}, {}, ["fevers:1", "streak:8"]),
        ("Inferno", "Fever with decoys and holds.",
         {"colors": [3, 4], "decoys": 1, "hold": 0.3}, {}, ["fevers:1", "ratio:70"]),
    ]),
    ("Memory", {"coins": 50, "theme": "ocean"}, [
        ("Remember", "BOSS: colors flash in the ball one at a time. Remember them, then hit them in that order.",
         {"colors": [1, 2]}, {"targets": 4, "bossEvery": 2, "bossLength": [3, 3], "ease": 3}, ["perfects:3", "streak:4"]),
        ("Long Memory", "Four colors to remember this time.",
         {"colors": [2, 2]}, {"targets": 6, "bossEvery": 2, "bossLength": [4, 4], "ease": 2}, ["perfects:6", "streak:5"]),
        ("Boss Rush", "A boss every other round, with NOT rounds in between.",
         {"colors": [3, 3], "inverted": 0.5}, {"targets": 9, "bossEvery": 2, "bossLength": [3, 4]}, ["perfects:8", "streak:6"]),
    ]),
    ("Mastery", {"coins": 500, "tokens": 3, "ball": "star"}, [
        ("Chaos", "Everything you have learned, mixed.",
         {"colors": [2, 4], "hold": 0.2, "reverse": 0.5, "decoys": 1, "rotate": 0.4, "bonus": 0.2, "inverted": 0.2, "split": 0.2, "ghost": 0.2, "locks": [3, 4]}, {"powerUpChance": 0.15}, None),
        ("Gauntlet", "Longer, with a boss in the middle.",
         {"colors": [3, 4], "hold": 0.2, "reverse": 0.6, "decoys": 1, "rotate": 0.5, "inverted": 0.25, "split": 0.25, "ghost": 0.25, "locks": [3, 5]}, {"addTargets": 4, "bossEvery": 11, "bossLength": [4, 4]}, None),
        ("Hue Master", "The final test. Three stars here means you have mastered Hue Lock.",
         {"colors": [3, 4], "hold": 0.2, "reverse": 0.6, "decoys": 1, "rotate": 0.6, "inverted": 0.3, "split": 0.3, "ghost": 0.3, "bonus": 0.2, "locks": [4, 5]}, {"addTargets": 6, "bossEvery": 13, "bossLength": [4, 4]}, None),
    ]),
]


def unlock_stars(chapter):
    """About half the stars of the chapters before it (1.5 per level)."""
    return round(chapter * 3 * 1.5)


def level(g, title, teaches, stage, extra, goals):
    """[g] is the level's 0-based position on the whole map."""
    ease = extra.get("ease", 0)
    d = max(0, g - ease)  # lessons play like an earlier level
    # "targets" sets the count; "addTargets" adjusts the usual one.
    targets = extra.get("targets", 8 + d // 3 + extra.get("addTargets", 0))
    out = {
        "title": title,
        "teaches": teaches,
        "targets": targets,
        "speed": round(90 + 2.2 * d) + extra.get("speedDelta", 0),
        "speedPerTarget": round(0.8 + 0.04 * d, 2),
        "size": round(64 - 0.6 * d + extra.get("sizeDelta", 0), 1),
        "sizePerTarget": round(-0.1 - 0.012 * d, 3),
        "stage": stage,
    }
    for k in ("powerUpChance", "powerUpTypes", "bossEvery", "bossLength"):
        if k in extra:
            out[k] = extra[k]
    if goals is None:
        hits = targets * (2 if stage.get("split", 0) >= 0.5 else 1)
        goals = [
            f"perfects:{max(2, math.ceil(targets * 0.5))}",
            f"streak:{min(hits, 3 + d // 5)}",
        ]
    out["goals"] = goals
    if extra.get("focus"):
        out["focus"] = True
    return out


def main():
    chapters = []
    g = 0
    for c, (title, reward, levels) in enumerate(CHAPTERS):
        built = []
        # Focus is available from the chapter that teaches it on.
        focus = any(t == "Focus" for t, _, _ in CHAPTERS[: c + 1])
        for title_, teaches, stage, extra, goals in levels:
            built.append(level(g, title_, teaches, stage, {**extra, "focus": focus}, goals))
            g += 1
        chapters.append({
            "title": title,
            "unlockStars": unlock_stars(c),
            "reward": reward,
            "levels": built,
        })
    comment = (
        "Generated by tool/generate_levels.py (edit it there). Each level overrides the base game_config.json: "
        "'stage' uses the same keys as a base stage (missing keys = off), 'speed' / 'size' are pointer deg/s and zone "
        "deg at the start, rising per target with speedPerTarget / sizePerTarget. Clearing a level is one star; each of "
        "its two 'goals' is another (see lib/game/star_goals.dart). A chapter opens at 'unlockStars' total stars and "
        "gives 'reward' once all its levels are cleared."
    )
    lines = ["{", f'  "_comment": {json.dumps(comment)},', '  "chapters": [']
    blocks = []
    for ch in chapters:
        rows = ",\n".join("        " + json.dumps(l, ensure_ascii=False) for l in ch["levels"])
        blocks.append(
            "    {\n"
            f'      "title": {json.dumps(ch["title"])},\n'
            f'      "unlockStars": {ch["unlockStars"]},\n'
            f'      "reward": {json.dumps(ch["reward"])},\n'
            '      "levels": [\n' + rows + "\n      ]\n    }"
        )
    lines.append(",\n".join(blocks))
    lines += ["  ]", "}", ""]
    with open(OUT, "w") as f:
        f.write("\n".join(lines))
    print(f"wrote {g} levels in {len(chapters)} chapters")


if __name__ == "__main__":
    main()
