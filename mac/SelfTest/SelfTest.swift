import AppKit
import AVFoundation
import WebKit

/// Called from hook.c before main: start once the app has launched.
@_cdecl("selftest_install")
public func selftestInstall() {
    // The sandbox's address, in the app's own settings before anything reads them; a
    // command-line default would win over every later change.
    if let base = UserDefaults.standard.string(forKey: "SelfTestBase") {
        UserDefaults.standard.set(base, forKey: Server.baseKey)
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
                                           object: nil, queue: .main) { _ in
        Task { @MainActor in await SelfTest.run() }
    }
}

/// Drives the real app from inside, against a Binah server (a sandbox copy, never the real
/// one: it makes a device token and saves a passage to train on). Keys are genuine NSEvents
/// posted to the app's own queue, so a key takes the path a keypress does. Pictures land in
/// -SelfTestOut.
@MainActor
enum SelfTest {
    static var failures = 0
    static var skipped = 0
    static var outDir: URL { URL(fileURLWithPath: UserDefaults.standard.string(forKey: "SelfTestOut") ?? NSTemporaryDirectory()) }

    /// -SelfTestOnly keys,menus,… runs some sections.
    static func wants(_ part: String) -> Bool {
        guard let only = UserDefaults.standard.string(forKey: "SelfTestOnly") else { return true }
        return only.split(separator: ",").contains { $0 == part }
    }

    static func run() async {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        log("SELFTEST against \(Server.base.absoluteString), token \(Token.value == nil ? "none" : "given")")
        // the sandbox's sign-in, as the page's own form would have left it
        if let given = UserDefaults.standard.string(forKey: "SelfTestCookie"),
           case let cookie = given.hasPrefix("c:") ? String(given.dropFirst(2)) : given,
           let host = Server.base.host,
           let c = HTTPCookie(properties: [.name: "binah", .value: cookie, .domain: host, .path: "/"]) {
            await WKWebsiteDataStore.default().httpCookieStore.setCookie(c)
        }
        _ = await until(10) { !BinahWindowController.all.isEmpty }
        guard let first = BinahWindowController.all.first, let w = first.window else {
            check(false, "a window opened")
            return finish()
        }
        // the page again, now signed in
        _ = await until(10) { !first.webView.isLoading }
        await js(first.webView, "window.__selftestOld = 1, 1")
        first.loadFromBase()
        let ready = await until(25) { await js(first.webView, "!window.__selftestOld && window.binahState && binahState().signedIn && binahState().total !== null ? 1 : 0") == "1" }
        check(ready, "Binah opens on Today, signed in", await js(first.webView, "document.body ? document.body.innerText.slice(0, 160) : ''"))
        guard ready else { return finish() }
        await front(w)
        await pause(1)
        capture(w, "01-today")
        dumpMenus()

        if wants("load") { await load(first) }
        if wants("window") { await window(first) }
        if wants("menus") { await menus(first) }
        if wants("keys") { await keys(first) }
        if wants("services") { await services(first) }
        if wants("outside") { await outside(first) }
        if wants("mic") { await mic(first) }
        if wants("deeplink") { await deeplink(first) }
        if wants("menubar") { await menubar() }
        if wants("connect") { await connect() }
        if wants("train") { await train() }
        if wants("settings") { await settings(first) }
        finish()
    }

    static func finish() {
        let note = skipped > 0 ? " (\(skipped) skipped: run again with the Mac left alone)" : ""
        log((failures == 0 ? "SELFTEST passed" : "SELFTEST \(failures) failed") + note)
        exit(failures == 0 ? 0 : 1)
    }

    static func route(_ web: WKWebView) async -> String { await js(web, "binahState().route") }

    // MARK: the sections

    /// The page knows it's in the Mac shell, and has the shell's half of the contract.
    static func load(_ c: BinahWindowController) async {
        let web = c.webView!
        check(await js(web, "navigator.userAgent").contains("Binah/\(UserAgent.version) (macOS shell)"), "the user agent names the shell")
        check(await js(web, "document.documentElement.classList.contains('shell') && document.documentElement.classList.contains('shell-mac')") == "1",
              "the page marks itself shell-mac")
        check(await js(web, "binahShell.platform + ' ' + binahShell.version") == "mac \(UserAgent.version)", "binahShell says mac and the version")
        check(await js(web, "['haptic','bars','share','openExternal','mic'].every(binahShell.can) && !binahShell.can('download')") == "1",
              "binahShell.can answers the five ops, and no others")
        // shell.js sends the page's ground at load
        let bars = await until(5) { ShellServices.heard.contains { $0.hasPrefix("bars #") } }
        check(bars, "the page sends its colours (bars)", ShellServices.heard.filter { $0.hasPrefix("bars") }.joined(separator: ", "))
        if let said = ShellServices.heard.last(where: { $0.hasPrefix("bars #") })?.split(separator: " ").dropFirst().first,
           let want = ShellServices.color(String(said)), let got = c.window?.backgroundColor.usingColorSpace(.sRGB) {
            let close = abs(got.redComponent - want.redComponent) + abs(got.greenComponent - want.greenComponent) + abs(got.blueComponent - want.blueComponent) < 0.02
            check(close, "the window's ground is the page's", "\(said)")
        }
    }

    /// Moshe's window: the lights in the strip over the rail, clear of the brand; the page's
    /// empty ground moves the window; full screen tells the page.
    static func window(_ c: BinahWindowController) async {
        guard let w = c.window, let close = w.standardWindowButton(.closeButton), let zoom = w.standardWindowButton(.zoomButton) else {
            return check(false, "the window has its traffic lights")
        }
        let closeAt = close.convert(close.bounds, to: nil), zoomAt = zoom.convert(zoom.bounds, to: nil)
        let topGap = w.frame.height - closeAt.maxY
        check(abs(closeAt.minX - 20) < 1.5 && abs(topGap - (BinahWindowController.stripHeight - closeAt.height) / 2) < 1.5,
              "the traffic lights sit 20 px in, in the middle of the 44 px strip", "x \(closeAt.minX), top gap \(topGap)")
        // where the brand and the rail are, in window points (the page's CSS px times the zoom)
        let geo = await js(c.webView, "JSON.stringify((() => { const r = document.querySelector('.rail').getBoundingClientRect(), b = document.querySelector('.brand').getBoundingClientRect(); return [r.width, b.top, getComputedStyle(document.querySelector('.rail')).paddingTop]; })())")
        if let data = geo.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: data) as? [Any], a.count == 3,
           let railW = a[0] as? Double, let brandTop = a[1] as? Double {
            let z = Double(c.webView.pageZoom)
            check(railW * z > Double(zoomAt.maxX) + 8, "the lights are over the rail", "rail \(railW * z), lights end \(zoomAt.maxX)")
            check(brandTop * z >= Double(topGap + closeAt.height) + 4, "the brand starts below the lights", "brand top \(brandTop * z), padding \(a[2])")
        } else {
            check(false, "the page has its rail and brand", geo)
        }
        check(w.minSize.width >= 900, "the window is never narrower than the two-column page")
        // a click in the top strip, over the page's column, reaches the page (a game's close
        // button sits there once the page scrolls)
        if let frameView = w.contentView?.superview {
            let at = NSPoint(x: w.frame.width / 2, y: w.frame.height - 12)
            let hit = frameView.hitTest(at)
            check(hit.map { $0 === c.webView || $0.isDescendant(of: c.webView) } ?? false, "a click in the top strip reaches the page",
                  hit.map { "\(type(of: $0))" } ?? "nothing")
        }
        // the sidebar's material behind a transparent web view, and the page told so
        let material = w.contentView as? NSVisualEffectView
        check(material?.material == .sidebar && material?.blendingMode == .behindWindow && c.webView.superview === material,
              "the window draws the sidebar material behind the page")
        check((c.webView.value(forKey: "drawsBackground") as? Bool) == false, "the web view draws no background of its own")
        check(await js(c.webView, "document.documentElement.classList.contains('shell-vibrant')") == "1", "the page is marked shell-vibrant")
        // what it looks like once the page leaves its rail transparent (the page's part, to come)
        await js(c.webView, "(() => { const s = document.createElement('style'); s.id = '__vibrant'; s.textContent = 'html, body, #app, .rail { background: transparent !important } #main { background: #fff }'; document.head.append(s); return 1; })()")
        await pause(0.6)
        capture(w, "02-vibrant-rail")
        await js(c.webView, "(document.getElementById('__vibrant').remove(), 1)")
        // AppKit lays the title bar out again on its own; the lights go back where they belong
        close.setFrameOrigin(NSPoint(x: 7, y: 7))
        _ = await until(2) { close.frame.origin.x == BinahWindowController.lightsInset }
        check(close.frame.origin.x == BinahWindowController.lightsInset, "the lights return when AppKit moves them", "\(close.frame.origin)")

        // the ground and the top strip ask to move the window; a control never does
        WindowMessages.received.removeAll()
        let press = { (sel: String, y: String) in
            "(() => { const t = document.querySelector('\(sel)'); const r = t.getBoundingClientRect(); t.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0, clientX: r.left + r.width / 2, clientY: \(y), detail: 1 })); return 1; })()"
        }
        await js(c.webView, press("#main", "300"))
        await js(c.webView, press(".rail", "500"))
        await js(c.webView, press(".nav button", "200"))
        await pause(0.3)
        check(WindowMessages.received.filter { $0 == "drag" }.count == 2, "empty ground moves the window, a button doesn't", WindowMessages.received.joined(separator: ","))

        // full screen: the class the page uses to drop the room it leaves for the lights
        guard await front(w) else { return skip("full screen") }
        w.toggleFullScreen(nil)
        let inFull = await until(6) { await js(c.webView, "document.documentElement.classList.contains('shell-fullscreen')") == "1" }
        await pause(1)
        capture(w, "03-fullscreen")
        check(inFull, "full screen puts shell-fullscreen on the page")
        let pad = await js(c.webView, "getComputedStyle(document.querySelector('.rail')).paddingTop")
        check(inFull && pad != "52px", "in full screen the rail takes its room back", pad)
        w.toggleFullScreen(nil)
        let out = await until(6) { await js(c.webView, "document.documentElement.classList.contains('shell-fullscreen')") == "0" }
        _ = await until(4) { !w.styleMask.contains(.fullScreen) }
        await pause(1)
        check(out, "leaving full screen takes it off again")
    }

    /// The Go menu runs the page's commands, ticks the place you're at, and greys Back
    /// when there's nowhere to go.
    static func menus(_ c: BinahWindowController) async {
        let web = c.webView!
        await choose("Practice")
        check(await until(5) { await route(web) == "practice" }, "Go → Practice goes there", await route(web))
        if let practice = find("Practice", in: NSApp.mainMenu!), let m = practice.menu {
            Menus.refresh(m)
            await pause(0.3)
            m.update()
            check(practice.state == .on && find("Skills", in: NSApp.mainMenu!)?.state == .off, "Practice, and only Practice, is ticked in the Go menu")
        }
        await pause(0.5)
        capture(c.window!, "04-practice")
        await choose("Skills")
        check(await until(5) { await route(web) == "skills" }, "Go → Skills goes there")
        await choose("Back")
        check(await until(5) { await route(web) == "practice" }, "Go → Back goes back", await route(web))
        await choose("Settings…")
        check(await until(5) { await route(web) == "settings" }, "Binah → Settings… is the page's Settings")
        await choose("Today")
        _ = await until(5) { await route(web) == "today" }
        Menus.refresh()
        await pause(0.3)
        if let back = find("Back", in: NSApp.mainMenu!), let m = back.menu {
            m.update()
            check(!back.isEnabled, "Back is greyed on Today with nowhere to go")
        }
    }

    /// The shell's keys run their command once.
    static func keys(_ c: BinahWindowController) async {
        let web = c.webView!
        guard await front(c.window!) else { return skip("keys") }
        let before = Menus.ran.count
        press("2", 19, .command)
        check(await until(5) { await route(web) == "practice" }, "⌘2 goes to Practice", await route(web))
        await pause(0.4)
        check(Menus.ran.count - before == 1, "⌘2 runs once", Menus.ran.suffix(3).joined(separator: ","))
        press("3", 20, .command)
        check(await until(5) { await route(web) == "skills" }, "⌘3 goes to Skills")
        press("[", 33, .command)
        check(await until(5) { await route(web) == "practice" }, "⌘[ goes back")
        press("1", 18, .command)
        _ = await until(5) { await route(web) == "today" }
        let z = Zoom.level
        press("=", 24, .command)
        await pause(0.3)
        check(Zoom.level > z && abs(web.pageZoom - Zoom.level) < 0.001, "⌘= zooms the page in", "\(z) → \(Zoom.level)")
        press("0", 29, .command)
        await pause(0.3)
        check(Zoom.level == 1, "⌘0 puts it back")
    }

    /// The page's calls into the Mac answer as SHELL.md says.
    static func services(_ c: BinahWindowController) async {
        let web = c.webView!
        check(await js(web, "binahShell.haptic('confirm')") == "1", "haptic answers true")
        check(await js(web, "binahShell.bars({ bg: '#123456', dark: true })") == "1", "bars answers true")
        let got = c.window?.backgroundColor.usingColorSpace(.sRGB)
        check(got.map { abs($0.redComponent - 0x12 / 255.0) < 0.01 && abs($0.blueComponent - 0x56 / 255.0) < 0.01 } ?? false,
              "bars colours the window")
        await js(web, "(() => { const css = getComputedStyle(document.documentElement); return binahShell.bars({ bg: css.getPropertyValue('--ground').trim(), dark: matchMedia('(prefers-color-scheme: dark)').matches }); })()")
        check(await js(web, "binahShell.share({ text: 'Passage', url: 'https://example.org/a' })") == "1", "share answers true")
        check(await js(web, "binahShell.share({})") == "0", "share with nothing answers false")
        let n = Outside.opened.count
        check(await js(web, "binahShell.openExternal('https://example.org/elsewhere')") == "1" && Outside.opened.count == n + 1,
              "openExternal opens the browser")
        check(await js(web, "binahShell.openExternal('file:///etc/hosts')") == "0", "openExternal won't open a file")
        check(await js(web, "binahShell.mic(true)") == "1" && c.recording, "mic(true): the window knows it's recording")
        check(await js(web, "binahShell.mic(false)") == "1" && !c.recording, "mic(false): and that it stopped")
        check(await js(web, "binahShell.nope ? 1 : 0") == "0", "there's nothing else on binahShell")
    }

    /// Only Binah loads in the window; the rest goes to the browser.
    static func outside(_ c: BinahWindowController) async {
        let web = c.webView!
        let n = Outside.opened.count
        await js(web, "(location.href = 'https://example.org/away', 1)")
        await pause(0.8)
        check(Outside.opened.count == n + 1 && Server.isOurs(web.url!), "a link elsewhere opens in the browser, the window stays",
              Outside.opened.last?.absoluteString ?? "")
        await js(web, "(window.open('https://example.com/blank', '_blank'), 1)")
        await pause(0.5)
        check(Outside.opened.last?.host == "example.com" && BinahWindowController.all.count == 1, "target=_blank elsewhere opens in the browser")
        await js(web, "(window.open(location.origin + '/#skills', '_blank'), 1)")
        check(await until(5) { BinahWindowController.all.count == 2 }, "target=_blank on Binah opens another Binah window")
        if BinahWindowController.all.count == 2, let second = BinahWindowController.all.last {
            _ = await until(10) { await js(second.webView, "window.binahState ? binahState().route : ''") == "skills" }
            check(await js(second.webView, "binahState().route") == "skills", "and it opens on that page")
            second.window?.performClose(nil)
            _ = await until(3) { BinahWindowController.all.count == 1 }
        }
        await front(c.window!)
    }

    /// The microphone: Binah's origin gets it, the camera never. getUserMedia exists only on
    /// https or localhost, so on a tailnet address this only checks that it's absent.
    static func mic(_ c: BinahWindowController) async {
        let web = c.webView!
        let secure = await js(web, "window.isSecureContext && !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)") == "1"
        guard secure else {
            log("INFO  \(Server.base.absoluteString) isn't a secure context, so the page can't record here; use https or localhost (ssh -L 8471:127.0.0.1:8471)")
            return
        }
        // macOS asks once whether this app may use the microphone, before WebKit asks Binah;
        // an unanswered prompt would hold getUserMedia forever
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            log("INFO  macOS hasn't asked about the microphone yet: run ./selftest.sh … mic and answer its prompt")
            if !wants("mic") || UserDefaults.standard.string(forKey: "SelfTestOnly") == nil { return }
        default:
            return log("INFO  the microphone is turned off for the test app in System Settings → Privacy & Security → Microphone")
        }
        BinahWindowController.micAnswers.removeAll()
        let audio = await js(web, """
            Promise.race([
              navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { const n = s.getAudioTracks().length; s.getTracks().forEach(t => t.stop()); return 'tracks ' + n; }),
              new Promise(r => setTimeout(() => r('waiting'), 30000)),
            ]).catch(e => 'refused ' + e.name)
            """)
        check(audio == "tracks 1", "getUserMedia gives the page one audio track", audio)
        check(BinahWindowController.micAnswers.contains { $0.hasSuffix("mic grant") }, "the shell granted it to Binah's origin",
              BinahWindowController.micAnswers.joined(separator: "; "))
        guard audio.hasPrefix("tracks") else { return }
        let camera = await js(web, """
            Promise.race([
              navigator.mediaDevices.getUserMedia({ video: true }).then(s => { s.getTracks().forEach(t => t.stop()); return 'given'; }),
              new Promise(r => setTimeout(() => r('waiting'), 5000)),
            ]).catch(e => 'refused')
            """)
        check(camera == "refused", "the camera is refused", camera)
    }

    /// binah://go/skills opens that page.
    static func deeplink(_ c: BinahWindowController) async {
        NSApp.delegate?.application?(NSApp, open: [URL(string: "binah://go/skills")!])
        check(await until(5) { await route(c.webView) == "skills" }, "binah://go/skills opens Skills", await route(c.webView))
        NSApp.delegate?.application?(NSApp, open: [URL(string: "binah://go/today")!])
        _ = await until(5) { await route(c.webView) == "today" }
    }

    /// The menu bar: today's edition, from /api/widget with the token.
    static func menubar() async {
        guard Token.value != nil else { return log("INFO  no token given: the menu bar check needs one") }
        await Today.shared.refresh()
        guard let w = Today.shared.widget else { return check(false, "the widget answers", Today.shared.problem ?? "") }
        check(MenuBar.shared.title == "\(w.done)/\(w.total)" + (w.finished ? " ✓" : ""), "the menu bar shows the edition", MenuBar.shared.title)
        check(MenuBar.shared.item?.button?.title == MenuBar.shared.title, "and the status item says it")
        log("INFO  menu bar: \(MenuBar.shared.title) · \(Today.shared.line)")
    }

    /// Connect This Mac makes a token with the window's sign-in.
    static func connect() async {
        let before = Token.value
        let said = await SettingsWindow.connect()
        check(said == nil && Token.value != nil && Token.value != before, "Connect This Mac makes a new device token", said ?? "")
        await Today.shared.refresh()
        check(Today.shared.widget != nil && Today.shared.problem == nil, "the new token reads the widget", Today.shared.problem ?? "")
    }

    /// Train on This sends a passage, and Binah's refusal of a few words comes back as said.
    static func train() async {
        let passage = "The selftest of the Mac shell sends this passage to the sandbox. It has more than twenty words, " +
            "so Binah takes it as a passage to train on, and the nightly run may make items from it."
        await TrainOnThis.send(passage, title: nil)
        check(TrainOnThis.sent.last?.hasPrefix("ok ") == true, "a passage is saved", TrainOnThis.sent.last ?? "")
        await TrainOnThis.send("too short", title: nil)
        check(TrainOnThis.sent.last?.hasPrefix("no ") == true, "a few words are refused, with Binah's reason", TrainOnThis.sent.last ?? "")
    }

    /// The address setting: a bad one is refused, the same one changes nothing.
    static func settings(_ c: BinahWindowController) async {
        check(!Server.setBase("not an address"), "a bad address is refused")
        let loads = c.webView.url
        check(Server.setBase(Server.base.absoluteString + "/"), "the same address with a slash is taken")
        await pause(0.5)
        check(c.webView.url == loads, "and doesn't reload the window")
        SettingsWindow.show()
        await pause(0.8)
        if let w = NSApp.windows.first(where: { $0.title == "Binah Mac App Settings" }) {
            capture(w, "05-settings")
            w.close()
        }
    }

    // MARK: helpers

    /// Picks a menu item as the mouse would.
    static func choose(_ title: String) async {
        guard let i = find(title, in: NSApp.mainMenu!), let m = i.menu else { return log("INFO  no menu item \(title)") }
        Menus.refresh(m)
        await pause(0.3)
        m.update()
        m.performActionForItem(at: m.index(of: i))
        await pause(0.2)
    }

    @discardableResult
    static func front(_ w: NSWindow) async -> Bool {
        if NSApp.isActive && w.isKeyWindow { return true }
        NSApp.bringForward()
        w.makeKeyAndOrderFront(nil)
        let ok = await until(3) { NSApp.isActive && w.isKeyWindow }
        if !ok { log("INFO  another app is in front; the next checks need Binah in front") }
        await pause(0.2)
        return ok
    }

    static func find(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for i in menu.items where !i.isHidden {
            if i.title == title { return i }
            if let sub = i.submenu, let hit = find(title, in: sub) { return hit }
        }
        return nil
    }

    @discardableResult
    static func js(_ web: WKWebView, _ src: String) async -> String {
        // promises are awaited, so fetch() answers come back as values
        do {
            let v = try await web.callAsyncJavaScript("return await (\(src))", arguments: [:], in: nil, contentWorld: .page)
            if let b = v as? Bool { return b ? "1" : "0" }
            return String(describing: v ?? "undefined")
        } catch { return "error: \(error.localizedDescription)" }
    }

    /// A key as the keyboard sends it.
    static func press(_ key: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                        characters: key, charactersIgnoringModifiers: key,
                                        isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
    static func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        log((ok ? "PASS  " : "FAIL  ") + what + (detail.isEmpty ? "" : "  [" + detail.replacingOccurrences(of: "\n", with: "⏎") + "]"))
        if !ok { failures += 1 }
    }
    static func skip(_ what: String) { log("SKIP  \(what): Binah couldn't come to the front"); skipped += 1 }
    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
    static func until(_ timeout: Double, _ cond: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat { if await cond() { return true }; await pause(0.15) } while Date() < end
        return false
    }

    /// The app's own windows, chrome and all; no Screen Recording permission needed for these.
    static func capture(_ w: NSWindow, _ name: String) {
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: outDir.appendingPathComponent(name + ".png"))
    }

    static func dumpMenus() {
        for top in NSApp.mainMenu?.items ?? [] {
            let items = (top.submenu?.items ?? []).filter { !$0.isSeparatorItem && !$0.isHidden }.map { i -> String in
                let m = i.keyEquivalentModifierMask
                let mods = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
                return i.keyEquivalent.isEmpty ? i.title : "\(i.title) \(mods)\(i.keyEquivalent.uppercased())"
            }
            log("MENU  \(top.title): " + items.joined(separator: " · "))
        }
    }
}
