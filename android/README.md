# Binah for Android

A WebView on the live site (`https://binah.tiresia.xyz` by default), which is the whole interface
and is phone first. The app adds today's edition on the home screen, Train on this in the share
sheet, the microphone for voice answers, and the few things a page can't do from inside a
WebView. The contract between page and app is `docs/SHELL.md`.

- **The app**: Binah between the status bar and the navigation bar (or the keyboard, which makes
  the window shorter so the page's tab bar stays on screen), with the page's own ground behind
  both bars (`binahShell.bars`), kept for the next start so it paints the same before the page
  loads. Back goes through the page first (`window.binahBack()`: out of a game, then the page
  before), and leaves only when there's nowhere to go. Only Binah loads in it: anything else
  goes to the browser. The user agent ends `Binah/<version> (Android shell)`.
- **`window.binahShell`** over a `MessagePort` (docs/SHELL.md §2): the app posts `"binah:port"`
  with the port to the main frame, addressed to Binah's origin, after each load; `shell.js`
  builds `binahShell` on it. `haptic` (confirm, reject, tick), `bars`, `share` (the share sheet),
  `openExternal`, and `mic` (the screen stays on while a voice answer records).
- **The microphone**: when the page asks for audio (`getUserMedia`, Just a Minute and the
  benchmark talk), the app grants it to Binah's own origin and nothing else, never the camera.
  Android asks once for the microphone; the app's settings say whether it's on and can ask
  again. The page can only record on https or localhost.
- **The widget**, 2×2 or 4×2 from the same widget (it picks by size): a ring of today's games
  with the count in it (`1/3`, `✓` once the edition is done); on the 4×2 the next game, the
  minutes left and the week. Material You colours, light or dark as the phone is. Tap it for
  Today. It asks `/api/widget` every half hour (Android's own refresh), when the phone is
  unlocked (at most every 15 minutes, while Binah's process is alive), and when you leave the
  app; if Binah can't be reached it keeps the last numbers, dimmed, and dims an edition from
  another day too.
- **Train on this**, in any app's share sheet: a link, or a passage of 20 words or more, goes to
  `/api/save`, and a card at the bottom says what Binah said. Tap the card for Today. A link with
  a few words around it sends the words as its title.
- **Long-press the icon**: Today, Practice, Skills, App settings.
- **`binah://go/<route>`** opens that page: `binah://go/practice`.

## The token

The widget and Train on this use a device token, never the window's cookie. Signing in is all it
takes: within a few seconds of signing in, if the phone has no token of its own, the app makes one
(`POST /api/devices {"name": "android-<model>"}` with the window's sign-in), and Binah's
`GET /api/devices` lists it under the phone's model. App settings → Connect this phone does the
same by hand. The token is kept encrypted with a key in the phone's keystore (`Server.java`),
without AndroidX. Until the phone is connected, Train on this sends with the window's sign-in.

## Build it

On the Mac: JDK 17 (temurin), the Android SDK in `~/android-sdk` (platform 36).

```sh
cd android
./release.sh                 # Binah-0.1.0.apk, signed with Dvarim's key as Daf and Moshe are
adb install -r Binah-0.1.0.apk
./gradlew assembleDebug      # the test build, "Binah dev" (xyz.tiresia.binah.debug), beside the real app
```

`release.sh` signs with `android/keystore.properties` if there is one, and otherwise with
Dvarim's (`dvarim/android/keystore.properties`, beside this repository). Git ignores both, and any
`*.keystore` and `*.apk`. No key or password is in this repository.

## Check it

```sh
ssh -fN -L 8471:127.0.0.1:8471 <your-server>              # the sandbox, on this Mac's localhost
android/check.sh http://localhost:8471 COOKIE TOKEN        # the phone plugged in and unlocked
```

BASE must be a sandbox, never the real Binah: the check makes this phone's token and saves a
passage to train on. COOKIE and TOKEN are as for `mac/selftest.sh` (see `mac/README.md`).
`check.sh` installs the test build, and `check.py` forwards the phone's `localhost:8472` through
this Mac to BASE (`adb reverse`), so the page is on localhost and can record. It checks, in the page
over DevTools and on the phone:
- the user agent and `binahShell` over the port;
- `bars`, `share`, `openExternal`, and `mic` keeping the screen on and letting it go;
- `getUserMedia` given one audio track and the camera refused (the check grants the test build
  the microphone for the run and takes it back after);
- Back through the page and out of the app;
- `binah://go/skills`, and a link elsewhere staying out of the window;
- Train on this, sent and refused;
- the widget's numbers kept, Settings → Connect this phone, and signing in connecting the phone by itself.

Pictures land in `android/build/check`.

## The pieces

| file | |
| --- | --- |
| `MainActivity.java` | the window: the WebView, Back, the microphone, the bars, links out, opening on a route |
| `Shell.java` | `window.binahShell`'s Android half, over the message port |
| `Server.java` | where Binah is, the token (encrypted), `/api/widget`, `/api/save`, `/api/devices` |
| `Widget.java` | the home-screen widget and the icon's shortcuts |
| `ShareActivity.java` | Train on this, from the share sheet |
| `SettingsActivity.java` | the app's own settings: the address, this phone, the microphone |
| `Binah.java` | the process: the widget asks again on unlock |
