# Releasing Hue Lock

The app, icon, splash screen, signing, store texts, screenshots and privacy
policy are ready. These are the steps only you can do: creating accounts and
pasting ids. Where a step says "send to Claude", paste the values in the
chat and they get wired in.

## 1. Google Play (Android)

1. **Developer account.** Sign up at https://play.google.com/console. There
   is a one-time $25 fee and an identity check.
   - New *personal* accounts must run a **closed test with at least 12
     testers for 14 days** before production. Plan for that.
2. **Upload key (already made).** You received
   `hue-lock-upload.jks` and `github-secrets.txt`.
   - Back both up somewhere private.
   - Add the 4 secrets from `github-secrets.txt` at
     github.com/DionysisAth/hue-lock → Settings → Secrets and variables →
     Actions → New repository secret.
   - From then on, every build's release page also has **`hue-lock.aab`**,
     the file to upload to Play.
3. **Create the app** in Play Console:
   - Name: "Hue Lock: Color Tap"
   - Type: Game
   - Free
4. **Fill in the listing and the policy forms** by copying from
   [store/listing.md](store/listing.md):
   - texts
   - category
   - content rating
   - target audience (13+)
   - data safety
   - ads declaration
   - privacy policy URL

   Upload `store/icon-512.png`, `store/feature-graphic.png` and the 7 images
   in `store/screenshots/`.
5. **Play App Signing.** Accept it when you create the first release. Google
   then keeps the real signing key, and your upload key can be reset if
   it's ever lost.
6. **In-app products.** Create the three products from
   [store/listing.md](store/listing.md#in-app-products) with exactly those
   ids. Play only lets you create them after an AAB with the billing library
   has been uploaded, so do it after step 7.
7. **Upload `hue-lock.aab`** to Testing → Closed testing (or Internal
   testing first), add testers, and roll out.

## 2. AdMob (ads)

1. Sign up at https://admob.google.com with the same Google account, and
   link it to the Play app once it exists.
2. Add the app: **Android**, "Hue Lock". Add it for **iOS** too if you'll
   publish there.
3. In each app, create **two ad units**:
   - **Interstitial**
   - **Rewarded**. The reward amount doesn't matter; the game decides it.
4. **Privacy & messaging:**
   - Create a **GDPR message**: required to show ads in the EU/UK.
   - On iOS, also create an **IDFA explainer message**.

   The app already shows these messages and has a "Privacy options" button.
5. **Send to Claude:**
   - Android app id: `ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`
   - Android interstitial unit: `ca-app-pub-…/…`
   - Android rewarded unit: `ca-app-pub-…/…`
   - The same three for iOS, if you're doing iOS

   They go into `android/app/src/main/AndroidManifest.xml`,
   `ios/Runner/Info.plist` and `lib/config/ad_ids.dart`.
6. After the app is live, add an **app-ads.txt** file. AdMob shows its
   contents. It must sit on a website listed as the developer website in the
   store listing. GitHub Pages for this repo works: send it to Claude.

Until the real ids are in, every build shows Google's test ads. The test APK
always shows test ads, so tapping your own ads never risks your account.
Never tap real ads in the store version.

## 3. Apple App Store (iOS)

The iOS project is set up (bundle id `com.nwbn.huelock`, icons, launch
screen, tracking prompt), but it can't be built here. You need:

1. An **Apple Developer account**: $99/year at https://developer.apple.com.
2. A **Mac with Xcode**, or a cloud build service with a free tier, such as
   Codemagic or GitHub Actions macOS runners. Ask Claude to set one up
   (needs App Store Connect API key secrets).
3. In App Store Connect:
   - Create the app.
   - Create the same 3 in-app purchases.
   - Fill in the privacy "nutrition label" (same answers as Play's data
     safety form).
   - Add the screenshots and the texts.

## 4. Optional, free: leaderboards, achievements, cloud save

Set up Play Games Services in Play Console (and Game Center in App Store
Connect), then send Claude:
- the project id
- the leaderboard ids
- the achievement ids

See the README section "Leaderboards, achievements, cloud save".

## Checklist before pressing "Publish"

- [ ] Real AdMob ids are in, and the GDPR message is published in AdMob
- [ ] Upload key secrets are added; the latest release page has `hue-lock.aab`
- [ ] In-app products are created and **active**
- [ ] Listing, content rating, target audience, data safety and ads
      declaration are complete
- [ ] Closed test done (12 testers × 14 days, for new personal accounts)
