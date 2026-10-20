# Binah for Mac

Binah's Mac app, in SwiftUI and AppKit, with no web view. It talks to Binah's JSON API (`docs/API.md`) with a device token, the way the Android app does. It is Binah, `xyz.tiresia.binah`, and connects as the device `mac`. It replaced the web-view Mac app on 20 October 2026, and it keeps its device token where that app kept its own, so a Mac connected before opens signed in.

## What's in it

- **The window.** The system's own window, sidebar and toolbar in macOS 26's glass look, with an inspector beside the games that have a reading pane:
  - the sidebar has Train (Today, Practice, Skills) and Measure (Golden Set, Benchmark), with counts from `/api/nav` and the week at its foot;
  - a game opens on top of its room, with the system's back button.
- **Today.** The edition and Continue, yesterday's recall card, the games as an inset list, the week and the totals.
- **Practice, Skills and the Golden Set.**
  - Practice is the games as cards, filtered by a segmented control in the toolbar.
  - Skills has the ratings, each with a Swift Charts sparkline, plus discernment, the self-rating gap and a way to the benchmark.
  - The Golden Set shows progress, the items to score, and Claude's agreement as a native table.
- **All seven games.**
  - Open answers follow the API's fixed order: answer with a 0–4 self-rating, Claude's verdict, one revision, then the reference. A grade that has to wait for tomorrow (`later`, `grading_later`) says so and offers the reference.
  - **Gist & Infer:** read, hide, then write the point in 20 words or fewer.
  - **Subtext:** the passage, with the question in the inspector.
  - **Cut the Bloat:** golf against par.
  - **Find the Weak Step:** pick a sentence, a flaw from a radio group, and an optional reason.
  - **The Author's Word:** the sentence with its gap, and the choices in the inspector.
  - **Technique or Fair Move?:** six calls, each with a confidence, then the round's Brier score and d′.
  - **Just a Minute:** recorded natively as AAC in an .m4a, with a countdown ring and live level bars. It stops at sixty seconds, keeps the Mac awake while recording, and shows the server's measurements and Claude's verdict.
- **The Golden Set's own flow.** Answer, see the key, then score yourself on the rubric's anchors.
- **The Benchmark.**
  - **The overview:** your sittings as a table.
  - **A sitting:** every answer is saved as you give it, and you can pick a choice with the keys 1–5 or A–E. The essay has a 15-minute timer and saves itself. The two-minute talk is recorded the same way as Just a Minute.
  - **The review:** the scores, the essay and the talk as their grades arrive, then every miss with its explanation.
- **Settings (⌘,).** Your rhythm and Claude's tone (kept on the server), your password and Sign Out, and this Mac's address and menu bar.
- **Train on This.** File → Train on This… (⇧⌘T), with whatever's on the clipboard offered, and Services → Train on This in Binah.
- **The menu bar.** Today's edition, `1/3` or `3/3 ✓`, with the edition, Practice and Train on This a click away. It can be turned off in Settings.
- **Links.** `binah://go/<route>` opens a room (`today`, `practice`, `skills`, `golden`, `bench`) or Settings (`settings`), for Shortcuts and the like.
- **The look.** New York, the system's serif, for passages. Binah's teal is the accent, lighter in dark mode, and the pillars have their colours and SF Symbols. The icon is layered as Icon Composer makes them (`Resources/AppIcon.icon`, from `web/icon.svg`).

## Build it

macOS 26 or later and Xcode (for `actool`, which compiles the icon).

```sh
cd mac
./build.sh                                    # build/Binah.app
ditto build/Binah.app /Applications/Binah.app
```

It signs with an Apple Development identity if the keychain has one, ad hoc otherwise. No team or identity is written into this repository. On first launch it asks you to sign in once, unless the Mac was connected before. After that it keeps a device token in the Keychain, and Binah's Settings lists it as `mac`.

## Test it

```sh
ssh -fN -L 8471:127.0.0.1:8471 <your-server>        # the sandbox, never the real Binah
./selftest.sh http://localhost:8471 TOKEN            # a sandbox device token
```

The test:
- decodes every endpoint the app reads;
- checks that one item from every game has the fields its game shows;
- opens every room and every game and pictures the window, in light and dark;
- plays The Author's Word once, end to end, which writes one answer to the sandbox.

It builds the app as "Binah Selftest" (`xyz.tiresia.binah.selftest`), so the real app's settings are never touched. The pictures and the log land in `build/selftest`.

## The pieces

| file | |
| --- | --- |
| `App/BinahApp.swift` | the app, its scenes (window, Settings, menu bar) and commands, Services |
| `Core/API.swift` | where Binah is, the device token, requests, uploads, sign-in, polling |
| `Core/Models.swift`, `Core/JSON.swift` | the API's answers as the app reads them |
| `Core/AppModel.swift` | the rooms, what's open, today and the sidebar's counts |
| `Core/Recorder.swift` | voice answers |
| `Views/` | the window and sidebar, Today, Practice, Skills, the Golden Set, Settings, shared pieces |
| `Games/` | the shared answer flow and the seven games, and the Golden Set's own flow |
| `Bench/Bench.swift` | the benchmark |
| `App/SelfTest.swift` | the self-test |
