# Hue Lock — Game Design Document

> **Purpose of this document:** This is the complete design spec for *Hue Lock* (working title — can be renamed). It is meant to be handed to a developer (or to Claude) as the brief for building the game. It explains the concept, gameplay, content, monetization, technical requirements and the first milestone (MVP).

---

## 1. Platform Requirement

**Hue Lock must run on both iOS and Android** from a single codebase.

- Target: iPhone/iPad (iOS) and Android phones/tablets.
- Orientation: **portrait** (one-handed play), with layouts that adapt to different screen sizes and notches.
- Performance target: a rock-solid **60 FPS** (120 FPS on supporting devices) with **very low input latency**. In a timing game, a dropped frame or delayed tap feels unfair.
- Small download size and fast startup (under 3 seconds to play).
- Must meet store requirements for both the **Apple App Store** and **Google Play** (in-app purchases, ads, privacy prompts, age ratings).

---

## 2. Concept Summary

**Hue Lock** is an **endless one-tap timing/reflex game** in the spirit of Flappy Bird and Stack, with a **color-matching twist**.

A **pointer sweeps around a ring**. The ring has **colored target zones**. The player's **ball has a color**. The player must **tap at the exact moment the pointer is inside a zone that matches the ball's color**.

- **Hit** → the ball "locks in", points are scored, and the next round starts slightly harder.
- **Miss** (wrong color or empty space) → game over.

Difficulty ramps up **forever**: faster pointers, smaller zones, more colors, rotating rings, decoy colors and direction changes. The goal is simply to beat your best score.

**Genre:** Hyper-casual endless reflex/timing game
**Target audience:** Very broad, ages 8+, anyone with a phone and 30 seconds to spare
**Session length:** Runs last 10–90 seconds; sessions are many quick runs in a row
**Business model:** Free-to-play with ads, continue tokens and cosmetic skins

---

## 3. Design Pillars

Every decision in the game should support these four ideas:

1. **One tap, zero learning** — The rules must be understandable from a single screenshot.
2. **Death is always the player's fault** — Timing must be precise and fair. If players feel cheated by lag or randomness, they quit.
3. **Instant restart** — Back in the game in **under half a second** after failing.
4. **"Just one more"** — Short runs, a visible high score and near-miss moments that make players think "I can beat that".

---

## 4. Controls

| Input | Action |
|---|---|
| **Tap** anywhere | Lock the pointer at its current position. Hit or miss is judged instantly. |
| **Tap** on the game-over screen | Restart immediately |

That's the whole game.

**Timing rules:**
- Hit detection uses the pointer's position at the **exact moment of the tap** (timestamped input, not the next frame).
- A tiny **grace margin** at zone edges (tunable, a few milliseconds) so hits that *look* correct always count.

---

## 5. Core Gameplay Loop

1. **Tap to start** a run.
2. **Each round:** the pointer sweeps the ring; tap when it's on a zone matching the ball's color.
3. **Hit** → score +1 (more for perfect hits), the next round is slightly harder.
4. **Miss** → game over screen: score, best score, coins earned.
5. Option to **continue** once (continue token or rewarded ad), otherwise **instant restart**.
6. **Spend coins** on skins, complete missions, try again.

---

## 6. Core Mechanic in Detail

### 6.1 The Ring

- A circle in the middle of the screen.
- Has **1 or more colored target zones** (arcs) on it.
- The rest of the ring is **neutral** (gray). Tapping there is a miss.

### 6.2 The Pointer

- A marker that **sweeps around the ring** at a set speed.
- Can move **clockwise**, **counterclockwise**, or **reverse direction** after each hit (in later stages).

### 6.3 The Ball

- Sits in the center of the ring and shows **the color you need to hit**.
- Changes color **between rounds** (and in later stages, sometimes **mid-round**).

### 6.4 Hit Types

| Hit type | Condition | Reward |
|---|---|---|
| **Perfect** | Pointer within the **center ~20%** of the zone | +3 points, combo increases, special effect + sound |
| **Good** | Pointer anywhere else inside the correct zone | +1 point |
| **Miss** | Wrong color zone, or neutral area | Game over |

- **Perfect combo:** several Perfect hits in a row raise a **score multiplier** (x2, x3...) and make the background glow. One Good hit resets the combo.
- **Near miss:** if the player misses by a tiny margin, show **"SO CLOSE!"** on the game-over screen. This is a strong "try again" trigger.

---

## 7. Difficulty Ramp (Infinite)

Difficulty increases with **score**. Each new element is introduced gradually and then mixed with earlier ones.

| Score range | What changes |
|---|---|
| **0–10** | 1 zone, matches the ball color. Slow pointer. Pure timing tutorial. |
| **10–25** | Zones get smaller, pointer gets faster. |
| **25–40** | **2 colors**: two zones of different colors; only the one matching the ball counts. |
| **40–60** | **Pointer reverses** direction after each hit. |
| **60–80** | **3–4 colors** on the ring, including **decoy zones** close to the right one. |
| **80–100** | **Rotating ring:** the ring itself slowly spins (in either direction) while the pointer moves. |
| **100–130** | **Shifting zones:** zones grow/shrink or slide during the round. |
| **130+** | **Ball color changes mid-round** (with a short warning flash). |
| **Beyond** | All mechanics mixed randomly; speed keeps increasing slowly up to a cap, then zones keep shrinking to a minimum size. |

**Tuning rules:**
- Difficulty should rise in a **wave**: a few harder rounds, then a slightly easier "breather" round.
- All speeds, zone sizes and thresholds live in a **config file** for easy tuning.
- Never generate impossible rounds: the correct zone must always be reachable before the pointer's next pass with a reasonable reaction time.

---

## 8. Game Modes

| Mode | Description | Purpose |
|---|---|---|
| **Endless** | The main mode described above. | Core game. |
| **Daily Challenge** | Same seeded sequence for everyone that day, with a **global leaderboard**. One free attempt, more via ad. | Daily return reason, fair competition. |
| **Zen mode** *(later)* | No game over, no score; relaxing practice. | Casual players, practice. |
| **Friend duel** *(later)* | Share a challenge link: "Beat my 87". Friend plays the same sequence. | Social virality. |

---

## 9. Progression & Retention

- **Best score** shown big on the home screen and during runs ("New best!" moment when passed).
- **Coins** earned per run (based on score) and from collectible coins that occasionally appear on the ring (hit a coin zone for a bonus).
- **Missions** (3 active at a time): "Get 5 Perfects in a row", "Score 50", "Play 10 runs". Completing missions gives coins and occasionally a skin.
- **Player level / XP** from playing, unlocking skins at milestones.
- **Daily login rewards** with streak bonuses.
- **Achievements** (Game Center / Google Play Games).

---

## 10. Viral & Retention Hooks

- **Score as a social challenge** — the game-over screen has a **"Challenge a friend"** button that shares the score with a link.
- **Clip sharing** — export the last ~10 seconds as a vertical 9:16 video with the score and game logo, especially after a **new best** or a long Perfect streak.
- **Daily Challenge leaderboard** — everyone plays the same sequence, so scores are directly comparable.
- **Visual intensity rises with score** — at high scores the game becomes fast, glowing and dramatic, which makes great video content.
- **Push notifications** (opt-in): "New Daily Challenge is live", "Your friend beat your score".

---

## 11. Monetization

**Rule:** Never sell anything that changes the timing or difficulty in leaderboard modes. Scores must always reflect skill.

### 11.1 Currencies

| Currency | How it's earned | What it buys |
|---|---|---|
| **Coins** (soft) | Runs, missions, daily rewards, rewarded ads | Skins, continue tokens |
| **Gems** (hard, optional) | Purchased; rare free drops | Premium skins, continue token packs |

*(A single coin currency plus direct real-money purchases may be enough for this genre; see Open Decisions.)*

### 11.2 Continue Tokens

- When the player fails, they can **continue the run once** from where they died.
- Paid with a **continue token**, **coins**, or a **rewarded ad**.
- **Maximum one continue per run** (keeps scores meaningful and avoids pay-to-win).
- **No continues in the Daily Challenge** (or they don't count toward the leaderboard).
- Continue tokens are sold in packs and given in rewards.

### 11.3 Cosmetics

| Item type | Examples |
|---|---|
| **Ball skins** | Planet, eyeball, donut, disco ball, emoji faces |
| **Pointer skins** | Comet, laser, arrow, paintbrush |
| **Ring themes** | Neon, candy, space, minimal, retro arcade |
| **Hit effects** | Fireworks, pixel burst, shockwave, confetti |
| **Background themes** | Gradient sets, animated starfields |
| **Sound packs** | 8-bit, piano, drum hits |

- Cosmetics must **never reduce readability** of colors and zones; every theme must keep zones clearly visible.
- **Colorblind mode** is free and always available (colors also get symbols/patterns).

### 11.4 Other Purchases

- **Remove ads** — the most important purchase in this genre. Removes interstitials (rewarded ads stay optional).
- **Starter Pack** — remove ads + coins + an exclusive skin, offered once.
- **Skin bundles** and themed packs.
- **Season pass** *(later)* — exclusive cosmetics through missions over 4–6 weeks.

### 11.5 Ads

Ads are the main revenue source for hyper-casual games, so they need careful balancing:

- **Interstitial ads**: after every **3–4 runs** (tunable), **never between death and the restart tap**, so the instant retry stays instant. A short gap before showing them is better (e.g. shown when returning to the home screen or after a run ends, never mid-flow).
- **Rewarded video ads**: continue a run, double coins after a run, extra Daily Challenge attempt, free coins.
- **Banner ads** *(optional)*: small banner on the home/game-over screen only, never during play.
- **No ads at all** during a player's first few runs.

---

## 12. Art Direction

- **Minimalist and bold:** clean geometric shapes, a dark or soft background, bright saturated colors for zones.
- **Readability above all:** zone colors must be clearly different from each other and from the background; each color also has a **symbol/pattern** for colorblind players.
- **Juice:** satisfying "lock" snap animation on hit, screen pulse on Perfect, glow intensity rising with combo and score.
- **Dramatic death:** brief slow-motion freeze-frame on the miss, showing where the pointer stopped versus where the zone was.

---

## 13. Audio

- A crisp, satisfying **"click/lock" sound** on every hit; a brighter sound on Perfect.
- **Rising pitch** for consecutive Perfects.
- Short, non-annoying fail sound.
- Background music that **intensifies with score** (layers added as you go higher).
- Separate music / sound volume controls, mute option, and **haptic feedback** (vibration) on hits, toggleable.

---

## 14. Technical Requirements

### 14.1 Platforms

- **iOS and Android**, built from **one shared codebase**.

### 14.2 Engine Options

This is a **very simple 2D game** (no physics, a handful of shapes) where the critical factors are **frame-perfect timing, low input latency, small app size** and good ads support.

| Option | Fit | Notes |
|---|---|---|
| **Unity** (recommended for ads-driven scale) | ✅ Best for monetization | The standard for hyper-casual; the best ads mediation and analytics support. Larger app size and more setup for a game this simple. |
| **Flutter + Flame** | ✅ Good fit | The game is simple vector shapes and UI, which Flutter renders smoothly. Small, fast, quick to build, and Google Mobile Ads with mediation works well. A strong option if the owner already knows Flutter. |
| **Godot** | ✅ Good fit | Lightweight, free, excellent for simple 2D. Ads/IAP plugins less mature than Unity's. |

All three can make this game well; the decision mostly depends on how important ads mediation tooling is versus development speed. **Final engine choice is an open decision** (see Section 19).

### 14.3 Implementation Notes

- **Timing accuracy:** game logic should use **delta time** and compute hits from the **input event timestamp**, so results don't depend on frame rate.
- **Test on low-end devices** for input latency and frame drops.
- **Seeded randomness:** round generation uses a seed so the **Daily Challenge** and **friend duels** produce the same sequence for everyone.
- **Fairness check:** generation must guarantee every round is beatable (Section 7).
- **All difficulty values in config / remote config** so the ramp can be tuned without app updates.
- **Instant restart:** no scene reload; reset game state in memory.
- **Leaderboard anti-cheat:** basic server-side validation of scores (e.g. reject impossible scores; optionally replay the seed + tap times to verify).
- **Save system:** local save + cloud save for coins, skins and best score.

### 14.4 Required Integrations

- **In-app purchases** (App Store + Google Play billing), with receipt validation
- **Ads SDK** with mediation (interstitial + rewarded, optional banner)
- **Analytics** (run lengths, where players die, ad frequency vs. retention, purchases)
- **Remote config**
- **Leaderboards & achievements** (Game Center / Google Play Games, or custom backend)
- **Native share sheet** + screen clip export
- **Haptics**
- **Privacy & consent** flows (Apple App Tracking Transparency, GDPR consent)

---

## 15. MVP Scope (First Milestone)

The goal of the MVP is to **test whether the core timing feels good and whether people play "just one more"**.

**Included in the MVP:**
- ✅ Runs on **iOS and Android**
- ✅ Ring, pointer, ball, one-tap hit detection with grace margin
- ✅ Perfect / Good / Miss + combo multiplier
- ✅ Difficulty ramp up to **~100 score** (single color → multiple colors → reversing pointer → rotating ring)
- ✅ Instant restart (< 0.5 s)
- ✅ Best score, coins, game-over screen with "SO CLOSE!"
- ✅ **5–8 ball skins** + 2 ring themes, bought with coins
- ✅ Continue (rewarded ad, once per run)
- ✅ Interstitial + rewarded ads, **Remove ads** purchase
- ✅ Colorblind mode, haptics, sound
- ✅ Local save + basic analytics

**Not in the MVP (later):**
- Daily Challenge & leaderboards
- Missions, XP levels, daily login rewards
- Clip sharing & friend challenges
- Gems, skin bundles, season pass
- Zen mode, friend duels
- Shifting zones & mid-round color changes

> **Key tests:** Does the timing feel *fair*? How many runs do players do per session? Track **Day 1 retention**, **average runs per session**, and **ad frequency vs. retention**.

---

## 16. Development Roadmap

1. **Prototype** — ring, pointer, tap, hit/miss, speed ramp. Tune timing and feel.
2. **MVP** — everything in Section 15. Test on real iOS and Android devices (including cheap ones).
3. **Soft launch** — release in a few countries, measure retention and ad revenue.
4. **Retention features** — missions, daily rewards, Daily Challenge, leaderboards.
5. **Virality** — clip sharing, friend challenges.
6. **More cosmetics** and the remaining difficulty mechanics.
7. **Global launch** + marketing with high-score clips.

---

## 17. Key Metrics to Track

- **Day 1 / Day 7 retention**
- Runs per session, sessions per day
- **Score distribution** (where most players die — tune the ramp around this)
- Continue usage rate
- Ads watched per user per day, interstitial frequency vs. churn
- Remove-ads purchase rate, overall conversion and revenue per user

---

## 18. Ideas for Later

- **Two-ring mode:** two rings side by side, tap left or right side of the screen.
- **Boss rounds** every 50 points: a special visually dramatic round with a unique pattern.
- **Seasonal themes** (Halloween, winter) with limited cosmetics.

---

## 19. Open Decisions

- [ ] **Final name** (Hue Lock is a working title)
- [ ] **Engine:** Unity, Flutter + Flame, or Godot?
- [ ] **Currencies:** coins only, or coins + gems?
- [ ] **Interstitial frequency:** every 3, 4 or 5 runs?
- [ ] **Leaderboards:** platform services (Game Center / Play Games) or custom backend?
- [ ] **Exact numbers:** speed curve, zone sizes, grace margin, skin prices
- [ ] **Art & audio:** in-house, asset packs, or hired?

---

## 20. Instructions for the Developer

When starting development from this document:

1. Start with the **Prototype** stage (Section 16, step 1). Focus only on timing feel and fairness.
2. The game **must build and run on both iOS and Android**.
3. Keep **all difficulty values in config** from day one (Section 14.3).
4. Prioritize, in order: **timing accuracy → instant restart → difficulty ramp → juice (effects/sound/haptics) → skins & coins → ads & monetization → retention & social features**.
5. Follow the **Design Pillars** (Section 3) whenever a decision is unclear.
