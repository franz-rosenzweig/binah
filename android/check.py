#!/usr/bin/env python3
"""The test build on the phone plugged into this Mac, against a sandbox Binah (check.sh).

    python3 -I check.py BASE COOKIE TOKEN

The phone reaches the sandbox through this Mac: its localhost:8472 is forwarded here (adb
reverse) and on to BASE, so the page is on localhost, a secure context, and can record. The
test build (xyz.tiresia.binah.debug, "Binah dev") opens on it with the token, the page is
signed in with the cookie over DevTools, and the checks run in the page, with keys pressed on
the phone, and through the share sheet's intent. Stdlib only.
"""
import base64
import json
import os
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET

PKG = "xyz.tiresia.binah.debug"
ACT = "xyz.tiresia.binah"
PORT = 8472
ADB = os.path.join(os.environ.get("ANDROID_HOME", os.path.expanduser("~/android-sdk")), "platform-tools", "adb")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "check")
failures = skipped = 0


def check(ok, what, detail=""):
    global failures
    print(("PASS  " if ok else "FAIL  ") + what + (f"  [{detail}]" if detail else ""), flush=True)
    if not ok:
        failures += 1


def adb(*args, check_=True):
    return subprocess.run([ADB, *args], capture_output=True, text=True, check=check_).stdout


def forward(listen_port, target):
    """localhost:listen_port → target (host:port), one thread per connection."""
    host, port = target.split(":")
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", listen_port))
    srv.listen(32)

    def pipe(a, b):
        """a → b until either end goes; then both are shut, and a (this direction's own) is closed
        and forgotten: a long sync opens hundreds of connections, more than a process may keep."""
        try:
            while True:
                d = a.recv(65536)
                if not d:
                    break
                b.sendall(d)
        except OSError:
            pass
        finally:
            for s in (a, b):
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            a.close()

    def serve():
        while True:
            c, _ = srv.accept()
            try:
                u = socket.create_connection((host, int(port)), timeout=10)
                u.settimeout(None)
            except OSError:
                c.close()
                continue
            threading.Thread(target=pipe, args=(c, u), daemon=True).start()
            threading.Thread(target=pipe, args=(u, c), daemon=True).start()

    threading.Thread(target=serve, daemon=True).start()


class WS:
    """Just enough of a WebSocket client for DevTools."""

    def __init__(self, url):
        hp, path = url[len("ws://"):].split("/", 1)
        h, p = hp.split(":")
        self.s = socket.create_connection((h, int(p)), timeout=300)   # a busy phone can be slow to answer DevTools
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {hp}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.n = 0

    def _recv(self, n):
        while len(self.rest) < n:
            self.rest += self.s.recv(65536)
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def read(self):
        payload = b""
        while True:
            b1, b2 = self._recv(2)
            ln = b2 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv(8))[0]
            payload += self._recv(ln)
            if b1 & 0x80:
                return json.loads(payload.decode("utf-8", "replace"))

    def send(self, method, **params):
        self.n += 1
        data = json.dumps({"id": self.n, "method": method, "params": params}).encode()
        ln = len(data)
        hdr = bytes([0x81]) + (bytes([0x80 | ln]) if ln < 126 else bytes([0x80 | 126]) + struct.pack(">H", ln) if ln < 65536
                               else bytes([0x80 | 127]) + struct.pack(">Q", ln))
        mask = os.urandom(4)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
        while True:
            m = self.read()
            if m.get("id") == self.n:
                return m.get("result", m)




def screenshot(name):
    """The phone's screen, for a look afterwards (build/check)."""
    os.makedirs(OUT, exist_ok=True)
    png = subprocess.run([ADB, "exec-out", "screencap", "-p"], capture_output=True, check=False).stdout
    if png:
        open(os.path.join(OUT, name + ".png"), "wb").write(png)


def ui_texts():
    """Every text on the screen now, from uiautomator."""
    adb("shell", "uiautomator", "dump", "/sdcard/binah-ui.xml", check_=False)
    xml = adb("shell", "cat", "/sdcard/binah-ui.xml", check_=False)
    adb("shell", "rm", "-f", "/sdcard/binah-ui.xml", check_=False)
    try:
        return [(n.get("text") or "", n.get("bounds") or "") for n in ET.fromstring(xml).iter("node")]
    except ET.ParseError:
        return []


def tap_text(text):
    """Taps the middle of the first node with this text. False if there's none."""
    for t, b in ui_texts():
        if t == text and b:
            x1, y1, x2, y2 = [int(v) for v in b.replace("][", ",").strip("[]").split(",")]
            adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def foreground():
    """The package whose activity is resumed now."""
    out = adb("shell", "dumpsys", "activity", "activities", check_=False)
    for line in out.splitlines():
        if "topResumedActivity" in line or "mResumedActivity" in line:
            return line
    return ""


def main(base, cookie, token):
    global skipped
    if "device" not in adb("get-state", check_=False):
        print("no phone: plug it in and allow USB debugging", file=sys.stderr)
        return 2
    forward(PORT, base.split("://", 1)[1].rstrip("/"))
    adb("reverse", f"tcp:{PORT}", f"tcp:{PORT}")
    awake = "mWakefulness=Awake" in adb("shell", "dumpsys", "power")
    locked = ("mDreamingLockscreen=true" in adb("shell", "dumpsys", "window") or
              "isKeyguardShowing=true" in adb("shell", "dumpsys", "window", "policy", check_=False)) if awake else True
    if locked:
        print("INFO  the phone is locked or asleep: the checks that press keys or read the screen are skipped", flush=True)
    adb("shell", "am", "force-stop", PKG)
    # the microphone for the test build only, for this run; taken back at the end
    had_mic = "android.permission.RECORD_AUDIO: granted=true" in adb("shell", "dumpsys", "package", PKG, check_=False)
    adb("shell", "pm", "grant", PKG, "android.permission.RECORD_AUDIO", check_=False)
    adb("shell", "am", "start", "-n", f"{PKG}/{ACT}.MainActivity",
        "--es", "binah.base", f"http://localhost:{PORT}", "--es", "binah.token", token)

    def attach():
        """DevTools on the test build's own WebView (webview_devtools_remote_<its pid>; other apps may have one)."""
        sock = None
        for _ in range(60):
            pid = adb("shell", "pidof", PKG, check_=False).strip()
            found = [l.split("@")[-1] for l in adb("shell", "cat", "/proc/net/unix").split() if "webview_devtools_remote" in l]
            mine = [f for f in found if pid and f.endswith("_" + pid)]
            if mine:
                sock = mine[-1].lstrip("@")
                break
            time.sleep(0.3)
        if not sock:
            return None
        adb("forward", "--remove", "tcp:9225", check_=False)
        adb("forward", "tcp:9225", f"localabstract:{sock}")
        for _ in range(40):
            try:
                pages = [t for t in json.load(urllib.request.urlopen("http://localhost:9225/json", timeout=5)) if t.get("type") == "page"]
                page = next((t for t in pages if f"localhost:{PORT}" in t.get("url", "")), None)
                if page:
                    return WS(page["webSocketDebuggerUrl"])
            except OSError:
                pass
            time.sleep(0.3)
        return None

    conn = {"ws": attach()}
    if not conn["ws"]:
        check(False, "the test build opens Binah, with DevTools")
        return 1

    def js(expr):
        r = conn["ws"].send("Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in r:
            return "error: " + str(r["exceptionDetails"].get("exception", {}).get("description", ""))[:200]
        return r.get("result", {}).get("value")

    def until(expr, secs=10):
        t0 = time.time()
        while time.time() - t0 < secs:
            if js(f"!!({expr})") is True:
                return True
            time.sleep(0.25)
        return False

    def route():
        return js("window.binahState ? binahState().route : ''")

    def finish():
        if not had_mic:
            adb("shell", "pm", "revoke", PKG, "android.permission.RECORD_AUDIO", check_=False)
        adb("reverse", "--remove", f"tcp:{PORT}", check_=False)
        adb("forward", "--remove", "tcp:9225", check_=False)
        note = f" ({skipped} skipped: unlock the phone and run again)" if skipped else ""
        print(("CHECK passed" if not failures else f"CHECK {failures} failed") + note, flush=True)
        return 1 if failures else 0

    conn["ws"].send("Network.enable")
    conn["ws"].send("Network.setCookie", name="binah", value=cookie, url=f"http://localhost:{PORT}")
    js("location.reload(), 1")
    time.sleep(1)
    check(until("window.binahState && binahState().signedIn && binahState().total !== null", 25), "Binah opens on the phone, signed in",
          str(js("document.body && document.body.innerText.slice(0, 80)")))

    # the contract: the user agent, the classes, and binahShell over the port
    ua = js("navigator.userAgent") or ""
    check(" Binah/" in ua and "(Android shell)" in ua, "the user agent names the shell", ua[-36:])
    check(js("['shell', 'shell-android'].every(c => document.documentElement.classList.contains(c))") is True,
          "shell.js marks the page shell-android", str(js("document.documentElement.className")))
    check(js("binahShell.platform === 'android' && ['haptic','bars','share','openExternal','mic'].every(binahShell.can)") is True,
          "window.binahShell is there, on Android")
    r = js("Promise.race([binahShell.haptic('confirm'), new Promise(r => setTimeout(() => r('no answer'), 5000))])")
    check(r is True, "the app answers over the message port (haptic)", str(r))
    r = js("Promise.race([binahShell.openExternal('ftp://nowhere'), new Promise(r => setTimeout(() => r('no answer'), 5000))])")
    check(r is False, "openExternal refuses what isn't a link", str(r))
    check(js("binahShell.share({})") is False, "share with nothing answers false")
    check(js("binahShell.bars({ bg: 'nonsense', dark: false })") is False, "bars refuses a colour that isn't one")
    check(js("(() => { const css = getComputedStyle(document.documentElement); return binahShell.bars({ bg: css.getPropertyValue('--ground').trim(), dark: matchMedia('(prefers-color-scheme: dark)').matches }); })()") is True,
          "bars takes the page's ground")

    def screen_kept_on():
        """Whether the app's window has FLAG_KEEP_SCREEN_ON (0x80): dumpsys prints the flags in hex."""
        lines = adb("shell", "dumpsys", "window", "windows", check_=False).splitlines()
        for i, l in enumerate(lines):
            if "Window{" in l and f"{PKG}/{ACT}.MainActivity" in l:
                for f in lines[i:i + 40]:
                    f = f.strip()
                    if f.startswith("fl="):
                        word = f[3:].split()[0]
                        try:
                            return bool(int(word, 16) & 0x80)
                        except ValueError:
                            return "KEEP_SCREEN_ON" in f
        return None

    def kept_on_detached():
        """The flag with DevTools let go: an attached DevTools session holds the screen on itself."""
        conn["ws"].s.close()
        time.sleep(1.2)
        on = screen_kept_on()
        conn["ws"] = attach()
        return on

    base_on = kept_on_detached()
    js("binahShell.mic(true)")
    on = kept_on_detached()
    check(on is True, "mic(true) keeps the screen on", f"{on}, before {base_on}")
    said = js("binahShell.mic(false)")
    on = kept_on_detached()
    check(on is False, "mic(false) lets it sleep again", f"{on}, answered {said}")

    # the microphone: the page's getUserMedia, granted to Binah's origin; the camera never
    check(js("window.isSecureContext && !!navigator.mediaDevices") is True, "the page is a secure context, so it can record")
    r = js("Promise.race([navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { const n = s.getAudioTracks().length; s.getTracks().forEach(t => t.stop()); return 'tracks ' + n; }), "
           "new Promise(r => setTimeout(() => r('waiting'), 15000))]).catch(e => 'refused ' + e.name)")
    check(r == "tracks 1", "getUserMedia gives the page one audio track", str(r))
    r = js("Promise.race([navigator.mediaDevices.getUserMedia({ video: true }).then(s => { s.getTracks().forEach(t => t.stop()); return 'given'; }), "
           "new Promise(r => setTimeout(() => r('waiting'), 8000))]).catch(e => 'refused')")
    check(r == "refused", "the camera is refused", str(r))
    screenshot("01-today")

    # Back: through the page, then out of the app
    if locked:
        skipped += 1
        print("SKIP  keys on the phone", flush=True)
    else:
        js("binahCommand('go:practice'), 1")
        until("binahState().route === 'practice'")
        time.sleep(0.6)
        screenshot("02-practice")
        js("binahCommand('go:skills'), 1")
        until("binahState().route === 'skills'")
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        check(until("binahState().route === 'practice'", 4), "Back goes back a page", str(route()))
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        check(until("binahState().route === 'today'", 4), "and back again to Today", str(route()))
        time.sleep(0.5)
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1.2)
        check(PKG not in foreground(), "on Today, Back leaves the app", foreground().strip()[:120])

    # binah://go/<route> opens that page (the app's window again, if Back left it)
    adb("shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", "binah://go/skills", PKG)
    time.sleep(1.5)
    check(until("binahState().route === 'skills'", 8), "binah://go/skills opens Skills", str(route()))

    # a link elsewhere leaves the window on Binah
    if not locked:
        js("(location.href = 'https://example.org/away', 1)")
        time.sleep(2)
        check(js("location.host") == f"localhost:{PORT}", "a link elsewhere doesn't load in the window", str(js("location.href")))
        adb("shell", "am", "start", "-n", f"{PKG}/{ACT}.MainActivity")
        time.sleep(1.5)

    # Train on this: a passage through the share sheet's intent, then a few words
    passage = ("The check of the Android shell sends this passage to the sandbox. It has more than twenty "
               "words, so Binah keeps it as a passage to train on later.")
    for text, want, what in ((passage, "Sent to Binah", "Train on this sends a passage"),
                             ("too short", "Not sent", "a few words are refused, with Binah's reason")):
        adb("shell", "am", "start", "-n", f"{PKG}/{ACT}.ShareActivity", "-a", "android.intent.action.SEND",
            "-t", "text/plain", "--es", "android.intent.extra.TEXT", f"'{text}'")
        if locked:
            time.sleep(3)
            continue
        time.sleep(1.2)                      # the card fades in, and Binah answers; reading the screen takes a while
        screenshot("03-share" if want.startswith("Sent") else "04-share-refused")
        seen = []
        for _ in range(8):
            seen = [t for t, _ in ui_texts() if t]
            if want in seen:
                break
            time.sleep(0.4)
        check(want in seen, what, " / ".join(t for t in seen if len(t) < 120)[:200])
        time.sleep(4)
    if locked:
        skipped += 1
        print("SKIP  the share card on the screen", flush=True)
    saved = js("fetch('/api/widget').then(r => r.ok)")
    check(saved is True, "the sandbox still answers after the shares", str(saved))

    # the widget's numbers: kept by the app when it goes to the background
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(3)
    prefs = adb("shell", "run-as", PKG, "cat", "shared_prefs/binah.xml", check_=False)
    check("widget.json" in prefs and "total" in prefs, "the app keeps /api/widget's answer for the widget", prefs[:0])

    # the app's settings: Connect makes this phone's token with the window's sign-in
    if locked:
        skipped += 1
        print("SKIP  Settings on the screen", flush=True)
    else:
        adb("shell", "am", "start", "-n", f"{PKG}/{ACT}.SettingsActivity")
        time.sleep(1.5)
        screenshot("05-settings")
        tapped = tap_text("Connect this phone")
        ok = False
        for _ in range(16):
            time.sleep(0.5)
            if any(t.startswith("Connected") for t, _ in ui_texts()):
                ok = True
                break
        check(tapped and ok, "Settings → Connect this phone connects it")
        adb("shell", "input", "keyevent", "KEYCODE_BACK")

    # signing in connects the phone by itself: no token, signed out, then the page's own sign-in
    # (the cookie, then what its form does next), and within seconds a token of this phone's own
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "am", "start", "-n", f"{PKG}/{ACT}.MainActivity", "--es", "binah.token", "-")
    conn["ws"] = attach()
    if not conn["ws"]:
        check(False, "the test build opens again, without a token")
        return finish()
    conn["ws"].send("Network.enable")
    conn["ws"].send("Network.clearBrowserCookies")
    js("location.reload(), 1")
    time.sleep(1)
    until("window.binahState && binahState().route === 'signin'", 15)
    time.sleep(5)
    token_kept = lambda: 'name="token"' in adb("shell", "run-as", PKG, "cat", "shared_prefs/binah.xml", check_=False)
    check(js("binahState().route") == "signin" and not token_kept(), "signed out, the phone has no token", str(js("binahState().route")))
    conn["ws"].send("Network.setCookie", name="binah", value=cookie, url=f"http://localhost:{PORT}")
    signed = js("import('/app.js').then(async m => { m.state.me = await (await fetch('/api/me')).json(); m.go('today'); return !!m.state.me.signed_in; })")
    t0 = time.time()
    while time.time() - t0 < 15 and not token_kept():
        time.sleep(0.5)
    check(signed is True and token_kept(), "signing in connects the phone within seconds", f"{signed}, {time.time() - t0:.1f} s")
    return finish()


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))
