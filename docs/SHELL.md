# The shell contract

How Binah's page and a native shell (`mac/`, `android/`) talk to each other. The page is the live site. A shell is a window around it plus the few things a page can't do on its own. This follows Daf's contract closely, trimmed to what Binah needs.

The page's half is `web/shell.js` plus three functions at the bottom of `web/app.js`. None of it does anything unless the user agent says a shell is there, so a plain browser never sees it.

## 1. The user agent

The shell appends one of these to the WebView's user agent:

- `Binah/<version> (macOS shell)`
- `Binah/<version> (Android shell)`

`shell.js` then puts `shell` and `shell-mac` or `shell-android` on `<html>`.

## 2. `window.binahShell`: the shell's, the page calls it

On the Mac the shell defines it at document start, before the page's scripts run, over a WebKit message handler named `binahShell`. On Android, `shell.js` defines it, and the calls go over a `MessagePort`: the app posts the string `"binah:port"` with the port to the main frame, addressed to Binah's origin. Calls made before the port arrives wait in a queue. Each call is JSON `{id, op, args}` on the port, and the app answers `{id, result}`.

| Call | What it does | Answers |
| --- | --- | --- |
| `can(op)` | Whether this shell has `op`. A missing op means: do what a browser would. | boolean |
| `haptic(kind)` | A tap felt in the hand: `confirm` (a right answer), `reject` (a miss) or `tick` (a selection, a tab). | Promise → `true` |
| `bars({bg, dark})` | The status and navigation bars (Android) or title bar (Mac) in the page's background colour `bg` (`#rrggbb`), with dark or light icons. `shell.js` sends it at load and whenever the colour scheme changes. | Promise → `true` |
| `share({text?, url?})` | The system share sheet. | Promise → `true`, or `false` if nothing was shared |
| `openExternal(url)` | Opens a link in the browser or the app it belongs to. | Promise → `true` |
| `mic(on)` | The page is recording a voice answer (`true`) or has stopped (`false`). Android keeps the screen on while recording; either shell may show a recording state. | Promise → `true` |

`binahShell.version` is the shell's version and `binahShell.platform` is `"mac"` or `"android"`.

**The microphone.** Just a Minute records with `getUserMedia` and `MediaRecorder` in the page. The Mac shell must answer WebKit's `requestMediaCapturePermission` (macOS 12 and later) for Binah's origin, and its Info.plist needs `NSMicrophoneUsageDescription`. The Android shell needs `RECORD_AUDIO` and must grant `WebChromeClient.onPermissionRequest` for `RESOURCE_AUDIO_CAPTURE` on Binah's origin only. The page uploads the recording itself (`POST /api/audio`).

## 3. `window.binahCommand(name)`: the page's, the shell calls it

This is how menus work. It answers `true` if the page did something and `false` if the command doesn't apply.

| Name | Does |
| --- | --- |
| `go:today` `go:practice` `go:skills` `go:golden` `go:settings` `go:bench` | Goes there (`bench` is the monthly benchmark) |
| `back` | The same as `binahBack()` |
| `reload` | Reloads the page |

## 4. `window.binahState()` and `window.binahBack()`

`binahState()` answers what a menu or the title needs:

```js
{ route: "today", signedIn: true, done: 1, total: 3, canBack: false }
```

`done` and `total` are today's edition, `null` until the page has loaded it.

`binahBack()` leaves a game (back to Today or Practice), or goes back in history. It answers `false` when there's nowhere to go, so Android can leave the app and the Mac can beep.

## 5. Devices

A shell connects itself once with the window's cookie, then uses a bearer token for anything it fetches outside the window (the widget, the menu bar):

- `POST /api/devices` `{"name": "mac"}` with the cookie → `{"name": "mac", "token": "…"}`. The token is shown only this once; keep it in the Keychain (Mac) or encrypted storage (Android). Posting the same name again replaces that device's token.
- `GET /api/devices` → `[{"name", "created", "last_seen"}]`
- `DELETE /api/devices/{name}` disconnects one.

Every `/api/` route accepts `Authorization: Bearer <token>` in place of the cookie.

## 6. The widget and the menu bar

`GET /api/widget` (bearer) →

```json
{"day": "2026-10-19", "done": 1, "total": 3, "finished": false, "minutes_left": 3,
 "next": {"game": "weak", "name": "Find the Weak Step"}, "week": {"active": 2, "goal": 4},
 "url": "https://binah.tiresia.xyz/#today", "deeplink": "binah://go/today"}
```

Poll it gently: once when the widget is shown, at most every 15 minutes in the background, and once after the app comes to the front.

## 7. Train on this (share target)

`POST /api/save` with either `{"url": "https://…", "title": "…"}` or `{"text": "a paragraph or more", "title": "…"}` → `{"ok": true, "id": 12, "open": "today", "message": "Saved. It becomes practice items in the next nightly run."}`. Show the message, and open `#today` if the user taps it. Text under 20 words without a URL is refused with a 400 and a plain message.

## 8. Deep links

`binah://go/<route>` opens the window at `<base>/#<route>`, for example `binah://go/today` or `binah://go/practice`. Routes are the hash routes of the page (`today`, `practice`, `skills`, `golden`, `settings`).

## 9. What the shell does on its own

- The Mac shell runs the page under a transparent title bar, so the traffic lights sit over the top of the rail. It puts `shell-fullscreen` on `<html>` while the window is in full screen (no lights then), and the page pads the rail only when that class is absent: `.shell-mac:not(.shell-fullscreen) .rail{padding-top:52px}`. The window is never narrower than 900px, so the rail always shows. Pressing empty ground (`html`, `body`, `#app`, `#main`, `.rail`) or the top 28px strip drags the window, unless the press is on a control.
- Only Binah's origin opens in the window. Any other address, including `target=_blank`, goes to the browser.
- The default base URL is `https://binah.tiresia.xyz`; a setting (or build flag) can point it at a sandbox, for example `http://<host>:8471`.
- Keep signing identities, team IDs, keystores and tokens out of the repo. It's public.
