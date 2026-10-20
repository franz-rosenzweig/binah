# Binah for macOS

A native shell around the live site (`https://binah.tiresia.xyz` by default). The page stays the
whole interface; the shell adds a proper Mac window, Binah's menus, today's edition in the menu
bar, Train on This from any app, and the microphone for voice answers. The contract between the
two is `docs/SHELL.md`.

- **The window**, in Moshe's look: the page runs to the top edge under a transparent title bar,
  and the traffic lights float over the top of the page's rail, which leaves room for them
  (`.shell-mac .rail`). Pressing the page's empty ground (around the column, the rail below its
  buttons) or its top 28 px strip moves the window, and a double-click zooms it, unless the
  press lands on a control. Full screen puts `shell-fullscreen` on the page so the rail takes its
  room back. Behind the page the window draws macOS's sidebar material (`NSVisualEffectView`,
  `.sidebar`, behind-window), and the web view draws no background of its own; the shell marks
  the page `shell-vibrant`, and where the page leaves itself transparent (its rail) the desktop
  shows through, blurred, as in Finder's sidebar. The frame is remembered; at least 900 × 600, so the page always has its two-column
  layout. Only Binah loads in the window: any other address opens in the browser.
- **The menus**: Binah (Settings… ⌘, is the page's own settings; Mac App Settings… ⌥⌘, is this
  app's), File (New Window ⌘N, Train on This… ⇧⌘T), Edit (with Spelling and Grammar for your
  written answers), View (Reload ⌘R, Actual Size ⌘0, Zoom In ⌘+, Zoom Out ⌘-, full screen ⌃⌘F),
  Go (Today ⌘1, Practice ⌘2, Skills ⌘3, Golden Set ⌘4, Benchmark ⌘5, Back ⌘[). Each Go item calls
  the page's own command (`window.binahCommand`). What's ticked and greyed comes from
  `window.binahState()`: the section you're in is ticked, and Back is greyed with nowhere to go.
- **`window.binahShell`** (docs/SHELL.md §2): `haptic` (felt on a Force Touch trackpad),
  `bars` (the window's ground follows the page's), `share` (the share picker), `openExternal`, and
  `mic` (while a voice answer records, the Mac doesn't sleep or dim the display, and closing,
  reloading or quitting asks first).
- **The microphone**: Binah's own origin gets it when the page asks (Just a Minute, the benchmark
  talk), never another origin and never the camera. macOS asks once whether Binah may use the
  microphone. The page can only record on https or localhost, so a sandbox on a tailnet address
  shows the games but can't take a voice answer.
- **Today in the menu bar**: `1/3`, or `3/3 ✓` once the edition is done, and ב until Binah has
  answered. Click it for the edition as dots, what's next, the week, and Play Today's Edition,
  Practice, Train on This…, Mac App Settings…. It asks `/api/widget` when the menu opens, every 15
  minutes, on wake, and when Binah comes to the front, and keeps the last answer, so offline it
  shows what it last knew (greyed after 20 minutes).
- **Train on This**: File → Train on This… (⇧⌘T) takes a link or a passage, offering what's on the
  clipboard. With text or a link selected in any app, Services → **Train on This in Binah** sends
  it straight away. Either way it goes to `/api/save`, and Binah's answer is shown, with Open Binah.
- **`binah://go/<route>`** opens that page, for Shortcuts and links: `binah://go/practice`.
- **Open at login** (Mac App Settings), where Binah starts in the menu bar without a window.

## The token

The menu bar and Train on This use a device token, never the window's cookie. Mac App Settings →
**Connect This Mac** makes one: it calls `POST /api/devices {"name": "mac"}` with the window's own
sign-in and keeps the answer in the login keychain. Binah's `GET /api/devices` lists it as "mac".
A token can be pasted there instead. Until the Mac is connected, Train on This sends with the
window's sign-in.

## Build it

macOS 14 or newer, the Command Line Tools (`xcode-select --install`), `brew install xcodegen`, and
`brew install librsvg` for the icon (it's drawn from `web/icon.svg`).

```sh
cd mac
./build.sh                                   # build/Binah.app, in about ten seconds
cp -R build/Binah.app /Applications/ && open /Applications/Binah.app
```

The build signs with an Apple Development identity if the keychain has one (Xcode → Settings →
Accounts, a free personal team is enough), ad hoc otherwise. With an ad hoc signature the Keychain
and the microphone ask again after each new build, because the signature changed. No team or
identity is written into this repository; `BINAH_SIGN=<identity>` picks another.

Services → Train on This in Binah appears once Binah has run from `/Applications`. If it doesn't,
turn it on in System Settings → Keyboard → Keyboard Shortcuts → Services → Text.

`xcodegen generate` in `mac/` makes `Binah.xcodeproj` from `project.yml` for anyone who would rather
use Xcode; both builds read the same settings. The project file and the Info.plist it writes are
not in git.

## Test it

```sh
# on the Mac: the sandbox on localhost, so the microphone works too
ssh -fN -L 8471:127.0.0.1:8471 <your-server>
curl -s -c /tmp/binah.cookies -o /dev/null -H 'content-type: application/json' \
     -d '{"user":"…","password":"…"}' http://localhost:8471/api/login
mac/selftest.sh http://localhost:8471 "$(awk '$6=="binah"{print $7}' /tmp/binah.cookies)" TOKEN
mac/selftest.sh http://localhost:8471 COOKIE TOKEN mic     # once, to answer macOS's microphone prompt
```

BASE must be a sandbox, never the real Binah: the test makes a device token named "mac" and saves a
passage to train on. It builds the app with `SelfTest/` linked in, as its own app
(`xyz.tiresia.binah.selftest`, so Binah can stay open), and checks:
- the user agent and `binahShell`;
- the traffic lights, over the rail and clear of the brand, and back when AppKit moves them;
- that a click in the top strip reaches the page;
- the window moving from empty ground, and full screen;
- every Go item and key running once, with the ticks and Back greyed;
- the five shell calls;
- links out;
- the microphone granted to Binah's origin and the camera refused;
- `binah://go/skills`, the menu bar, Connect This Mac, Train on This, and the address setting.

It takes the keyboard for about half a minute. Pictures land in `mac/build/selftest/out`.

## The pieces

| file | |
| --- | --- |
| `BinahApp.swift` | the app: launching, login items, `binah://` links, reopening, quitting while recording |
| `Window.swift` | the window, the traffic lights, moving it from the page, the microphone, links out, alerts |
| `Menus.swift` | the menu bar and what its items call |
| `ShellServices.swift` | `window.binahShell` |
| `Server.swift` | where Binah is, the device token in the Keychain, `/api/widget` and `/api/save` |
| `MenuBar.swift` | today's edition in the menu bar |
| `SettingsWindow.swift` | Mac App Settings: the address, Connect This Mac, the menu bar, open at login |
| `TrainOnThis.swift` | File → Train on This… and the Services item |
