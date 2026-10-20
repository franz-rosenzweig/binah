# The shell contract

How Binah's page and the Android app (`android/`) talk to each other. The page is the live site, and the Android app is a window around it plus the few things a page can't do on its own. This follows Daf's contract closely, trimmed to what Binah needs.

The Mac app (`mac/`) doesn't wrap the page any more: it's native SwiftUI and talks to the JSON API directly ([API.md](API.md)). Only the device, widget, Train on this and deep-link sections below apply to it.

The page's half is `web/shell.js` plus three functions at the bottom of `web/app.js`. None of it does anything unless the user agent says a shell is there, so a plain browser never sees it.

## 1. The user agent

The app appends `Binah/<version> (Android shell)` to the WebView's user agent, and `shell.js` then puts `shell` and `shell-android` on `<html>`.

## 2. `window.binahShell`: the shell's, the page calls it

`shell.js` defines it, and the calls go over a `MessagePort`: the app posts the string `"binah:port"` with the port to the main frame, addressed to Binah's origin. Calls made before the port arrives wait in a queue. Each call is JSON `{id, op, args}` on the port, and the app answers `{id, result}`.

| Call | What it does | Answers |
| --- | --- | --- |
| `can(op)` | Whether this shell has `op`. A missing op means: do what a browser would. | boolean |
| `haptic(kind)` | A tap felt in the hand: `confirm` (a right answer), `reject` (a miss) or `tick` (a selection, a tab). | Promise → `true` |
| `bars({bg, dark})` | The status and navigation bars in the page's background colour `bg` (`#rrggbb`), with dark or light icons. `shell.js` sends it at load and whenever the colour scheme changes. | Promise → `true` |
| `share({text?, url?})` | The system share sheet. | Promise → `true`, or `false` if nothing was shared |
| `openExternal(url)` | Opens a link in the browser or the app it belongs to. | Promise → `true` |
| `mic(on)` | The page is recording a voice answer (`true`) or has stopped (`false`). The app keeps the screen on while recording and may show a recording state. | Promise → `true` |

`binahShell.version` is the app's version and `binahShell.platform` is `"android"`.

**The microphone.** Just a Minute records with `getUserMedia` and `MediaRecorder` in the page. The Android app needs `RECORD_AUDIO` and must grant `WebChromeClient.onPermissionRequest` for `RESOURCE_AUDIO_CAPTURE` on Binah's origin only. The page uploads the recording itself (`POST /api/audio`).

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

`binahBack()` leaves a game (back to Today or Practice), or goes back in history. It answers `false` when there's nowhere to go, so Android can leave the app.

## 5. Devices

An app connects itself once with a sign-in cookie, then uses a bearer token for anything it fetches with it (the Android widget, the Mac app, its menu bar):

- `POST /api/devices` `{"name": "android-sm-s926u"}` with the cookie → `{"name": "android-sm-s926u", "token": "…"}`. The token is shown only this once; keep it in the Keychain (Mac) or encrypted storage (Android). Posting the same name again replaces that device's token.
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

`POST /api/save` with either `{"url": "https://…", "title": "…"}` or `{"text": "a paragraph or more", "title": "…"}` → `{"ok": true, "id": 12, "open": "today", "message": "Saved for later. Binah doesn't turn saved passages into practice yet."}`. Show the message, and open `#today` if the user taps it. Text under 20 words without a URL is refused with a 400 and a plain message.

## 8. Deep links

`binah://go/<route>` opens the window at `<base>/#<route>`, for example `binah://go/today` or `binah://go/practice`. Routes are the hash routes of the page (`today`, `practice`, `skills`, `golden`, `settings`).

## 9. What the shell does on its own

- The page picks its own look: Material 3 (it puts `m3` on `<html>`) when the window is under 900px wide, and always under `shell-android`; otherwise a look close to Apple's own apps, with a sidebar and a 52px toolbar row.
- Devices name themselves `android-<model>` (for example `android-sm-s926u`), so two phones don't replace each other's token. The native Mac app is `mac`.
- Only Binah's origin opens in the window. Any other address, including `target=_blank`, goes to the browser.
- The default base URL is `https://binah.tiresia.xyz`; a setting (or build flag) can point it at a sandbox, for example `http://<host>:8471`.
- Keep signing identities, team IDs, keystores and tokens out of the repo. It's public.
