# Binah for Android

Binah's Android app in Kotlin and Jetpack Compose (Material 3), with no web view. It talks to Binah's JSON API (`docs/API.md`) with a device token, as the Mac app does. It is Binah, `xyz.tiresia.binah`, and connects as the device `android-<model>` (`android-sm-s926u`). It replaced the WebView app on 20 October 2026 as an update to it (see [Replacing the WebView app](#replacing-the-webview-app)).

## What's in it

- **The window.** Edge to edge, with a Material 3 navigation bar: Today, Practice, Skills, Golden set. A game, the benchmark and Settings open on top, with a top app bar and Back.
- **Today.** A large title with the date, and the edition in a primary-container card: the next game, the games done as a wavy progress line, and Continue. Then yesterday's recall card, the games as a segmented list with each pillar's tonal icon, the week as day circles (the rest day dashed), and the totals.
- **Practice, Skills and the Golden set.**
  - Practice is the games as cards, filtered by pillar with chips.
  - Skills has the ratings with sparklines, discernment, the self-rating gap, and a way to the benchmark.
  - The Golden set shows progress, the items to score, and Claude's agreement as a table.
- **All seven games**, each on one scrolling column that moves down to the result when it arrives.
  - Open answers follow the API's fixed order: answer with a 0–4 self-rating, Claude's verdict, one revision, then the reference. A grade that has to wait for tomorrow (`later`, `grading_later`) says so and offers the reference.
  - **Gist & Infer:** read, hide, then write the point in 20 words or fewer.
  - **Subtext:** the passage, the question, your answer.
  - **Cut the Bloat:** golf against par.
  - **Find the Weak Step:** tap a sentence, pick a flaw, and optionally say why.
  - **The Author's Word:** the sentence with its gap, filled once you choose.
  - **Technique or Fair Move?:** six calls, each with a confidence, then the round's Brier score and d′.
  - **Just a Minute:** the topic card, a countdown ring, live level bars and a big stop button. It records AAC in an .m4a (`MediaRecorder`), stops at sixty seconds, keeps the screen on while recording, and shows the server's measurements and Claude's verdict.
- **The Golden set's own flow.** Answer, see the key, then score yourself on the rubric's anchors.
- **The benchmark.** The overview, a sitting (every answer saved as you give it, the essay with its 15-minute timer saving itself, the two-minute talk recorded like Just a Minute), and the review as the essay's and the talk's grades arrive.
- **Settings.** Your rhythm and Claude's tone (kept on the server), the microphone, your password, and this phone's address and Sign out.
- **The widget**, 2×2 or 4×2: a ring of today's games with the count in it; on the 4×2 the next game, the minutes left and the week. Material You colours. It asks `/api/widget` every half hour, on unlock (at most every 15 minutes) and when you leave the app, and keeps the last numbers, dimmed, if Binah can't be reached.
- **Train on this** in any app's share sheet: a link, or a passage of 20 words or more, goes to `/api/save`, and a card says what Binah said.
- **Long-press the icon:** Today, Practice, Skills, Settings.
- **Links.** `binah://go/<room>` opens a room (`today`, `practice`, `skills`, `golden`, `bench`, `settings`), for Shortcuts and the like.
- **Haptics** on a verdict (confirm or reject) and on picks.

## Build it

On the Mac: JDK 17 (temurin) and the Android SDK in `~/android-sdk` (platform 36). Gradle 8.14, the Android Gradle plugin 8.13, Kotlin 2.4 and the Compose BOM 2026.06.

```sh
cd android
./release.sh                       # Binah-0.2.0.apk, signed with Dvarim's key as Daf and Moshe are
adb install -r Binah-0.2.0.apk
./gradlew assembleDebug            # the test build, "Binah dev" (xyz.tiresia.binah.debug), beside the real app
```

`release.sh` signs with `android/keystore.properties` if there is one, and otherwise with Dvarim's (`dvarim/android/keystore.properties`, beside this repository). Git ignores both, and any `*.keystore` and `*.apk`. No key or password is in this repository. On first launch the app asks you to sign in once, then keeps a device token, encrypted with a key in the phone's keystore.

## Check it

```sh
ssh -fN -L 8471:127.0.0.1:8471 <your-server>       # the sandbox, never the real Binah
./check.sh http://localhost:8471 TOKEN              # a sandbox device token; the phone plugged in and unlocked
```

`check.sh` installs the test build, points the phone's `localhost` at this Mac's (`adb reverse`), and starts the app's self-test (`platform/SelfTest.kt`, in the test build only). The test:
- decodes every endpoint the app reads;
- checks that one item from every game has the fields its game shows;
- opens every room and every game, and the script pictures each, in light and dark;
- plays The Author's Word once, end to end, which writes one answer to the sandbox.

The pictures and the log land in `build/check`. Placing the widget can't be done from adb, so check it by hand.

## Replacing the WebView app

Until 20 October 2026 Binah for Android was a WebView around the page. This app took its place as an update to it, so nothing had to be reinstalled or signed in again:
- the same id (`xyz.tiresia.binah`), a higher `versionCode` (2), and the same signing key;
- the token kept exactly where and as that app kept it (prefs `binah`, `token`, IV then AES-GCM under the keystore key `binah-token-key`), and the same device name;
- the old components' names kept: the launcher entry and the share target as aliases (`xyz.tiresia.binah.MainActivity`, `xyz.tiresia.binah.ShareActivity`), and the widget as `xyz.tiresia.binah.Widget`, so the icon, a pinned share target and a placed widget all survive the update;
- `binah://go/<room>` and the shortcuts' ids (`today`, `practice`, `skills`, `settings`) as before; a route the old app sent as `#today` still works.

## The pieces

| file | |
| --- | --- |
| `MainActivity.kt` | the process and the window: opening on a room, the test build's sandbox extras |
| `core/Api.kt` | where Binah is, the device token (encrypted), requests, uploads, sign-in, polling |
| `core/Models.kt` | the API's answers as the app reads them |
| `core/AppModel.kt` | signed in or not, today and the counts, the toast, sending an answer |
| `ui/Root.kt` | the navigation bar and routes, the top bars, sign-in |
| `ui/Rooms.kt` | Today, Practice, Skills, the Golden set, Settings |
| `ui/Theme.kt`, `ui/Common.kt` | Material 3 colours from Binah's teal, the pillars, and shared pieces |
| `games/` | the shared answer flow, the seven games, and the Golden set's own flow |
| `bench/Bench.kt` | the benchmark |
| `platform/Recorder.kt` | voice answers |
| `platform/Platform.kt` | the widget, the shortcuts, Train on this |
| `platform/SelfTest.kt` | the self-test |
| `xyz/tiresia/binah/Widget.kt` | the widget under the WebView app's name for it |
