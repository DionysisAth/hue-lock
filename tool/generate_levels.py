#!/usr/bin/env python3
"""Writes assets/config/levels.json: 12 chapters x 5 levels.

Difficulty rises slowly and evenly over the whole map (pointer speed, zone
size and target count follow the level's position), and every chapter opens
with an easier lesson level for its new mechanic. Edit the tables below and
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
         {"colors": [2, 2]}, {}, None),
        ("Pick the Right One", "Three colors on the ring. Find the ball's color first, then wait for it.",
         {"colors": [2, 3]}, {}, None),
        ("Warm-Up Run", "Clear the dots above the ball in a row for a set bonus.",
         {"colors": [2, 3], "locks": [2, 3]}, {}, None),
    ]),
    ("Turnaround", {"coins": 50, "ball": "bullseye"}, [
        ("About Face", "REVERSE: the pointer flips direction after every hit.",
         {"colors": [1, 1], "reverse": 1}, {"ease": 1}, None),
        ("Back and Forth", "Sometimes it flips, sometimes it doesn't. Watch the pointer, not the clock.",
         {"colors": [2, 2], "reverse": 0.6}, {}, None),
        ("Switchback", "Every hit flips it, with more colors to choose from.",
         {"colors": [2, 3], "reverse": 1}, {}, None),
        ("Ping Pong", "Short hops back and forth. Stay calm.",
         {"colors": [2, 3], "reverse": 0.8, "locks": [2, 3]}, {}, None),
        ("Turnabout", "Three colors, flips and lock sets together.",
         {"colors": [3, 3], "reverse": 0.7, "locks": [2, 4]}, {}, None),
    ]),
    ("Gold Rush", {"coins": 150, "tokens": 1}, [
        ("Greedy", "GREEDY: a thin gold-rimmed zone is worth +5. Go for it, or wait for the safe one.",
         {"colors": [1, 2], "bonus": 0.8}, {"ease": 1}, ["greedy:1", "greedy:3"]),
        ("Power-Ups", "Badges ride on targets: hit the target to collect them. Shield, slow-mo and wide.",
         {"colors": [2, 2]}, {"powerUpChance": 0.4}, ["powerUps:1", "streak:4"]),
        ("Shield Up", "A shield absorbs one miss. Keep it to the end for a star.",
         {"colors": [2, 3], "reverse": 0.3}, {"powerUpChance": 0.4, "powerUpTypes": ["shield"]}, ["shield", "streak:4"]),
        ("Lucky Streak", "Gold zones and power-ups. Greed is good, sometimes.",
         {"colors": [2, 3], "bonus": 0.5, "locks": [2, 3]}, {"powerUpChance": 0.3}, ["greedy:1", "streak:5"]),
        ("Treasure Hunt", "Everything so far, with gold on top.",
         {"colors": [2, 3], "bonus": 0.5, "reverse": 0.5, "locks": [2, 4]}, {"powerUpChance": 0.2}, None),
    ]),
    ("Opposites", {"theme": "sunset"}, [
        ("Not That One", "NOT: the ball shows a crossed-out color. Hit any color EXCEPT that one.",
         {"colors": [3, 3], "inverted": 1}, {"ease": 1}, None),
        ("Anything But", "NOT rounds now and then. Read the ball before you tap.",
         {"colors": [3, 3], "inverted": 0.5}, {}, None),
        ("Mixed Signals", "NOT rounds and flips together.",
         {"colors": [3, 3], "inverted": 0.4, "reverse": 0.5}, {}, None),
        ("Double Negative", "Four colors, lots of NOTs.",
         {"colors": [3, 4], "inverted": 0.5}, {}, None),
        ("Contrary", "NOT, flips and gold zones.",
         {"colors": [3, 4], "inverted": 0.4, "reverse": 0.6, "bonus": 0.3}, {}, None),
    ]),
    ("Decoys", {"coins": 200}, [
        ("Decoys", "DECOYS: a wrong color sits right next to the right one. Tap a little early or late and you lose.",
         {"colors": [3, 3], "decoys": 1}, {"ease": 1}, None),
        ("Close Call", "Decoys on every round. Aim for the middle.",
         {"colors": [3, 4], "decoys": 1}, {}, ["perfects:6", "ratio:60"]),
        ("Fakeout", "Decoys and flips.",
         {"colors": [3, 4], "decoys": 1, "reverse": 0.6}, {}, None),
        ("Near Miss", "Decoys with NOT rounds: the wrong color might be the right one.",
         {"colors": [3, 4], "decoys": 1, "inverted": 0.3}, {}, None),
        ("Hall of Mirrors", "Decoys, flips and NOTs together.",
         {"colors": [3, 4], "decoys": 1, "reverse": 0.6, "inverted": 0.3, "locks": [2, 4]}, {}, None),
    ]),
    ("Spin Cycle", {"coins": 50, "ball": "swirl"}, [
        ("Carousel", "SPIN: the ring turns too, so zones move while the pointer moves.",
         {"colors": [2, 2], "rotate": 1}, {"ease": 1}, None),
        ("Merry-Go-Round", "Spinning rings with more colors.",
         {"colors": [2, 3], "rotate": 0.8}, {}, None),
        ("Counterspin", "The ring and the pointer don't always turn the same way.",
         {"colors": [2, 3], "rotate": 1, "reverse": 0.5}, {}, None),
        ("Whirl", "Spin and decoys.",
         {"colors": [3, 4], "rotate": 0.8, "decoys": 1}, {}, None),
        ("Tilt-a-Whirl", "Spin, flips and NOTs.",
         {"colors": [3, 4], "rotate": 0.7, "reverse": 0.5, "inverted": 0.3}, {}, None),
    ]),
    ("Ghosts", {"coins": 150, "tokens": 1}, [
        ("Ghosts", "GHOST: zones blink in and out. They always start visible: remember where they are.",
         {"colors": [2, 2], "ghost": 1}, {"ease": 1}, None),
        ("Now You See It", "More ghosts, more colors.",
         {"colors": [2, 3], "ghost": 0.7}, {}, None),
        ("Haunted Carousel", "Spinning ghosts. Watch the ring, not just the pointer.",
         {"colors": [2, 3], "ghost": 0.7, "rotate": 0.6}, {}, None),
        ("Poltergeist", "Ghosts, flips and decoys.",
         {"colors": [3, 4], "ghost": 0.6, "reverse": 0.6, "decoys": 1}, {}, None),
        ("Seance", "Ghosts, NOTs and spin.",
         {"colors": [3, 4], "ghost": 0.6, "inverted": 0.3, "rotate": 0.4}, {}, None),
    ]),
    ("Split Second", {"theme": "ocean"}, [
        ("Two at Once", "SPLIT: the ball is two colors. Hit the left one first, then the right one, in one lap.",
         {"colors": [2, 3], "split": 1}, {"ease": 1, "addTargets": -2}, None),
        ("Split Decision", "Splits that change direction. The second color is always after the first.",
         {"colors": [2, 4], "split": 0.7, "reverse": 1}, {}, None),
        ("Double Take", "Splits with four colors.",
         {"colors": [3, 4], "split": 0.6}, {}, None),
        ("Splitting Hairs", "Splits and decoys.",
         {"colors": [3, 4], "split": 0.5, "decoys": 1}, {}, None),
        ("Divide and Conquer", "Splits, NOTs and spin.",
         {"colors": [3, 4], "split": 0.5, "inverted": 0.3, "rotate": 0.4}, {}, None),
    ]),
    ("Fever Pitch", {"coins": 250, "tokens": 1}, [
        ("Fever Pitch", "5 Perfects in a row starts FEVER: double points and a faster pointer. A Good ends it.",
         {"colors": [1, 2]}, {"ease": 1}, ["fevers:1", "streak:6"]),
        ("Heat Wave", "Every Perfect during Fever scores double. Keep it going.",
         {"colors": [2, 2]}, {}, ["fevers:1", "streak:8"]),
        ("Hot and Cold", "Fever through flips.",
         {"colors": [2, 3], "reverse": 0.6}, {}, ["fevers:1", "streak:7"]),
        ("Wildfire", "Fever on a spinning ring.",
         {"colors": [2, 3], "rotate": 0.5}, {}, ["fevers:1", "streak:8"]),
        ("Inferno", "Fever with decoys and flips.",
         {"colors": [3, 4], "decoys": 1, "reverse": 0.5}, {}, ["fevers:1", "ratio:75"]),
    ]),
    ("Memory", {"coins": 50, "ball": "star"}, [
        ("Remember", "BOSS: colors flash in the ball one at a time. Remember them, then hit them in that order.",
         {"colors": [1, 2]}, {"targets": 4, "bossEvery": 2, "bossLength": [3, 3], "ease": 2}, ["perfects:3", "streak:4"]),
        ("Recall", "Two bosses, with normal rounds between them.",
         {"colors": [2, 2]}, {"targets": 6, "bossEvery": 2, "bossLength": [3, 3]}, ["perfects:5", "streak:5"]),
        ("Long Memory", "Four colors to remember this time.",
         {"colors": [2, 2]}, {"targets": 6, "bossEvery": 2, "bossLength": [4, 4]}, ["perfects:6", "streak:5"]),
        ("Boss Rush", "A boss every other round, with NOT rounds in between.",
         {"colors": [3, 3], "inverted": 0.5}, {"targets": 8, "bossEvery": 2, "bossLength": [3, 4]}, ["perfects:8", "streak:6"]),
        ("Mind Palace", "Long sequences between flips.",
         {"colors": [3, 3], "reverse": 0.5}, {"targets": 9, "bossEvery": 3, "bossLength": [4, 4]}, ["perfects:9", "streak:6"]),
    ]),
    ("Combo Craft", {"coins": 300, "tokens": 2}, [
        ("Steady Hands", "Every 3 Perfects in a row raise your combo multiplier, up to x5. A Good resets it.",
         {"colors": [1, 2]}, {"ease": 1}, ["combo:3", "streak:6"]),
        ("Rhythm", "Long Perfect streaks on a calm ring.",
         {"colors": [2, 2]}, {}, ["combo:4", "streak:9"]),
        ("Flow", "Keep the combo going through flips.",
         {"colors": [2, 3], "reverse": 0.5}, {}, ["combo:4", "ratio:70"]),
        ("In the Zone", "Keep the combo going on a spinning ring.",
         {"colors": [2, 3], "rotate": 0.4}, {}, ["combo:5", "ratio:70"]),
        ("Perfectionist", "Nothing but Perfects.",
         {"colors": [2, 3], "reverse": 0.4, "decoys": 1}, {}, ["combo:5", "ratio:80"]),
    ]),
    ("Mastery", {"coins": 500, "tokens": 3}, [
        ("Chaos", "Everything you have learned, mixed.",
         {"colors": [2, 4], "reverse": 0.5, "decoys": 1, "rotate": 0.4, "bonus": 0.2, "inverted": 0.2, "split": 0.2, "ghost": 0.2, "locks": [3, 4]}, {"powerUpChance": 0.15}, None),
        ("Gauntlet", "Longer, with a boss in the middle.",
         {"colors": [3, 4], "reverse": 0.6, "decoys": 1, "rotate": 0.5, "inverted": 0.25, "split": 0.25, "ghost": 0.25, "locks": [3, 5]}, {"addTargets": 4, "bossEvery": 11, "bossLength": [4, 4]}, None),
        ("Storm", "Fast spins and ghosts.",
         {"colors": [3, 4], "reverse": 0.6, "rotate": 0.7, "ghost": 0.3, "decoys": 1}, {}, None),
        ("Endgame", "No mercy: decoys, splits and NOTs.",
         {"colors": [3, 4], "reverse": 0.6, "decoys": 1, "inverted": 0.35, "split": 0.35, "rotate": 0.4}, {}, None),
        ("Hue Master", "The final test. Three stars here means you have mastered Hue Lock.",
         {"colors": [3, 4], "reverse": 0.6, "decoys": 1, "rotate": 0.6, "inverted": 0.3, "split": 0.3, "ghost": 0.3, "bonus": 0.2, "locks": [4, 5]}, {"addTargets": 6, "bossEvery": 13, "bossLength": [4, 4]}, None),
    ]),
]


def unlock_stars(chapter):
    """About half the stars of the chapters before it (1.5 per level)."""
    return round(chapter * 5 * 1.5)


def level(g, title, teaches, stage, extra, goals):
    """[g] is the level's 0-based position on the whole map."""
    ease = extra.get("ease", 0)
    d = max(0, g - 3 * ease)  # lessons play like a few levels earlier
    # "targets" sets the count; "addTargets" adjusts the usual one.
    targets = extra.get("targets", 8 + d // 5 + extra.get("addTargets", 0))
    out = {
        "title": title,
        "teaches": teaches,
        "targets": targets,
        "speed": round(90 + 1.1 * d),
        "speedPerTarget": round(0.8 + 0.02 * d, 2),
        "size": round(64 - 0.3 * d, 1),
        "sizePerTarget": round(-0.1 - 0.006 * d, 3),
        "stage": stage,
    }
    for k in ("powerUpChance", "powerUpTypes", "bossEvery", "bossLength"):
        if k in extra:
            out[k] = extra[k]
    if goals is None:
        hits = targets * (2 if stage.get("split", 0) >= 0.5 else 1)
        goals = [
            f"perfects:{max(2, math.ceil(targets * 0.5))}",
            f"streak:{min(hits, 3 + d // 9)}",
        ]
    out["goals"] = goals
    return out


def main():
    chapters = []
    g = 0
    for c, (title, reward, levels) in enumerate(CHAPTERS):
        built = []
        for spec in levels:
            built.append(level(g, *spec))
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
