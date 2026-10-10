# Store listing: copy, paste, done

Everything the Play Console and App Store Connect ask for when you create
the listing. Graphics are in this folder:

| File | Where it goes |
|---|---|
| `icon-512.png` | Play: App icon |
| `feature-graphic.png` | Play: Feature graphic (1024×500) |
| `screenshots/*.png` | Play: Phone screenshots. App Store: 6.5"/6.9" screenshots |

To regenerate them:
1. Run `python3 tool/generate_icon.py`.
2. Run `flutter test tool/store_screenshots_test.dart`.
3. Run `python3 tool/frame_screenshots.py`.

## Basics

- **App name:** Hue Lock: Color Tap
- **Package / bundle id:** com.nwbn.huelock
- **Category:** Games → Arcade. Tags: Casual, Reflex, Single player,
  Offline, Abstract.
- **Price:** Free, with ads and in-app purchases.
- **Privacy policy URL:**
  https://github.com/DionysisAth/hue-lock/blob/main/docs/privacy-policy.md

## Short description (80 characters max)

> Tap when the pointer hits the ball's color. One tap, pure timing, endless fun.

## Full description

> **One tap. Pure timing.**
>
> A pointer sweeps around a ring of colors. Tap when it's over the color of
> the ball. Hit it and the next round gets a little faster. Miss and it's
> over. Easy to learn, impossible to put down.
>
> **Chase the Perfect.** Hit the bright center of a zone for a PERFECT. Chain
> them to build your combo up to x5, while the music and the ring heat up
> with you.
>
> **Rules that flip on you.**
> - NOT rounds: hit any color *except* the ball's.
> - Split balls: two colors in one lap.
> - Boss rounds: watch the sequence, then play it back.
> - Ghost zones, a spinning ring, and a pointer that surges and reverses.
>
> **Build your run.** Beat a boss and pick one of three perks: a wider
> Perfect window, a shield, a slower pointer, a combo saver, more coins...
> Every run plays a little differently.
>
> **Ways to play**
> - **Endless:** how far can you go? Stages change every 20 rounds.
> - **Levels:** a map of 60 levels in 12 chapters that teach every trick. Each
>   level has three star goals; stars open new chapters and exclusive balls
>   and rings.
> - **Daily Challenge:** the same run for everyone, every day.
> - **Leaderboards:** climb the weekly rankings on Google Play Games, and
>   see exactly how many points it takes to pass the next player.
> - **Zen:** no game over, just flow.
> - **Duel:** send a friend a code. They play your exact run and try to beat
>   your score.
>
> **Keep coming back for more:** missions, daily rewards, player levels,
> achievements, and balls and rings to unlock.
>
> Plays offline. Colorblind mode included.

## In-app products

Create these in Play Console (Monetize → In-app products) and in App Store
Connect (In-App Purchases). Use exactly these product ids:

| Product id | Type | Suggested price | What it is |
|---|---|---|---|
| `hue_lock_remove_ads` | Non-consumable (managed) | $2.99 | No more interstitial ads |
| `hue_lock_starter_pack` | Non-consumable (managed) | $4.99 | Remove ads, 1000 coins, 5 continue tokens, the Crown ball |
| `hue_lock_tokens_5` | Consumable | $0.99 | 5 continue tokens |

## Content rating questionnaire (IARC)

- **Category:** Game.
- **Violence, fear, sex, language, drugs, gambling:** No to all.
- **Users can interact or exchange content:** No. A duel code is typed in by
  the player; there is no chat.
- **Shares location:** No.
- **Digital purchases:** Yes.
- **Ads:** Yes.

Expected rating: Everyone / PEGI 3 / 4+.

## Target audience (Play)

Choose **13 and over**. Younger age groups pull in the Families policy and
need extra ad settings.

## Data safety form (Play)

Answer for the app with ads and Google Play Games (leaderboards and cloud
save) turned on.

**Does your app collect or share user data?** Yes. Google AdMob does.

| Data type | Collected | Shared | Purpose | Optional? |
|---|---|---|---|---|
| Device or other IDs (advertising ID) | Yes | Yes | Advertising or marketing, Fraud prevention | No |
| Approximate location (from IP) | Yes | Yes | Advertising or marketing, Fraud prevention | No |
| App interactions | Yes | Yes | Advertising or marketing, Analytics | No |
| Crash logs, Diagnostics | Yes | Yes | Analytics, Fraud prevention | No |

- **Is all data encrypted in transit?** Yes.
- **Can users request deletion?** Users can reset their advertising ID in
  device settings, and uninstalling removes all app data. Answer "No" to
  "provide a way to request deletion", since we hold no data ourselves.
- **Purchases:** handled by Google Play Billing, nothing to declare.

Play Games adds, collected by Google Play Games (not by us) only for
players who sign in:

| Data type | Collected | Shared | Purpose | Optional? |
|---|---|---|---|---|
| Game progress (In-app activity: "Other actions") | Yes | No | App functionality | Yes |
| User IDs (Play Games player id) | Yes | No | App functionality | Yes |

## App access, ads and other declarations

- **App access:** all functionality is available without special access.
- **Contains ads:** Yes.
- **Advertising ID:** Yes. It is used for advertising and analytics by
  AdMob, and the manifest already includes the permission via the AdMob SDK.
- **Government app / financial features / health:** No.
- **News app:** No.
