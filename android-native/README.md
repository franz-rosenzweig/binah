# Binah for Android, native

Binah's Android app in Kotlin and Jetpack Compose (Material 3), with no web view. It talks to Binah's JSON API (`docs/API.md`) with a device token, as the Mac app does. For now it's a separate app beside the WebView app in `android/`: "Binah (native)", `xyz.tiresia.binah.nativeapp`, connecting as the device `android-native-<model>`, so both work at once. Once it covers everything, it takes the WebView app's place (see [Switching over](#switching-over)).

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
- **Train on this (native)** in any app's share sheet: a link, or a passage of 20 words or more, goes to `/api/save`, and a card says what Binah said.
- **Long-press the icon:** Today, Practice, Skills, Settings.
- **Links.** `binah-native://go/<room>` opens a room (`today`, `practice`, `skills`, `golden`, `bench`, `settings`). `binah://` stays the WebView app's until the switch-over.
- **Haptics** on a verdict (confirm or reject) and on picks.

## Build it

On the Mac: JDK 17 (temurin) and the Android SDK in `~/android-sdk` (platform 36). Gradle 8.14, the Android Gradle plugin 8.13, Kotlin 2.4 and the Compose BOM 2026.06.

```sh
cd android-native
./release.sh                       # BinahNative-0.1.0.apk, signed as the WebView app is
adb install -r BinahNative-0.1.0.apk
./gradlew assembleDebug            # the test build, "Binah native dev" (xyz.tiresia.binah.nativeapp.debug)
```

`release.sh` signs with `android-native/keystore.properties` if there is one, and otherwise with Dvarim's (`dvarim/android/keystore.properties`, beside this repository), the key the WebView app uses. Git ignores both, and any `*.keystore` and `*.apk`. No key or password is in this repository. On first launch the app asks you to sign in once, then keeps a device token, encrypted with a key in the phone's keystore.

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

## Switching over

When it covers everything, it becomes Binah for Android and the WebView app in `android/` goes:
1. In `app/build.gradle.kts`: `applicationId = "xyz.tiresia.binah"`, a `versionCode` above the WebView app's (1), and the names "Binah", "Train on this" and "Binah: today's edition".
2. In `core/Api.kt`: the token key becomes `binah-token-key` and the device name `android-<model>` (24 characters at most), as the WebView app has them. Signed with the same key, the native app then installs as an update over the WebView app, and the phone stays signed in.
3. In the manifest: the link scheme becomes `binah`.
4. `android-native/` becomes `android/`, and the docs (`docs/SHELL.md`, `docs/DEVELOPING.md`, `docs/install.md`, the README) say Android is native too.

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
