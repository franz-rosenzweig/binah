import AppKit
import WebKit

/// One Binah window, in Moshe's look: all page. The content runs to the top edge under a
/// transparent title bar, the traffic lights float over the top of the page's rail (the
/// page leaves room for them, docs/SHELL.md §9), and the page draws everything else.
@MainActor
final class BinahWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    /// Every open window, the way the menu finds the one in front.
    static private(set) var all: [BinahWindowController] = []

    /// The strip across the top the traffic lights sit in the middle of. The rail's
    /// padding (52 px) clears it.
    static let stripHeight: CGFloat = 44
    /// Where the close button starts, as in a window with a unified toolbar.
    static let lightsInset: CGFloat = 20
    /// Never narrower than the page's two-column layout (style.css, 900 px), so the
    /// rail, and the room it leaves for the lights, is always there.
    static let minSize = NSSize(width: 900, height: 600)
    private static let autosaveName = "Binah Window"

    private(set) var webView: ShellWebView!
    private let services = ShellServices()
    private lazy var windowMessages = WindowMessages(owner: self)

    /// The window in front, or any window.
    static var front: BinahWindowController? {
        for window in [NSApp.keyWindow, NSApp.mainWindow] {
            if let c = window?.windowController as? BinahWindowController { return c }
        }
        return all.first
    }

    /// A new window, on one of the page's routes ("#practice") or on Today.
    @discardableResult
    static func open(_ route: String? = nil) -> BinahWindowController {
        let c = BinahWindowController(route: route)
        all.append(c)
        c.showWindow(nil)
        c.layoutTrafficLights()
        return c
    }

    /// That page in the window in front, or in a new window if there is none.
    static func show(_ route: String) {
        NSApp.bringForward()
        if let c = all.first(where: { $0.window?.isVisible == true }) ?? all.first {
            c.window?.makeKeyAndOrderFront(nil)
            c.go(route)
        } else {
            open(route)
        }
    }

    init(route: String?) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Binah"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.minSize = Self.minSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        // the page's ground, until the page says (bars)
        window.backgroundColor = NSColor(name: nil) { look in
            look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x1b / 255.0, green: 0x1d / 255.0, blue: 0x2b / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xec / 255.0, green: 0xe3 / 255.0, blue: 0xd7 / 255.0, alpha: 1)
        }
        super.init(window: window)
        window.delegate = self
        // The frame is remembered for the first window of the app; another one opens
        // cascaded from the window in front.
        if !Self.all.contains(where: { $0.window?.frameAutosaveName == Self.autosaveName }) {
            if !window.setFrameUsingName(Self.autosaveName) { window.center() }
            window.setFrameAutosaveName(Self.autosaveName)
        } else if let front = Self.front?.window {
            window.setFrame(front.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        }
        makeWebView(route)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    // MARK: the page

    private func makeWebView(_ route: String?) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // the sign-in cookie outlives a launch
        config.applicationNameForUserAgent = UserAgent.name
        config.mediaTypesRequiringUserActionForPlayback = []   // the reference answer's audio plays when asked
        let content = config.userContentController
        content.addUserScript(WKUserScript(source: ShellServices.script, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true, in: .page))
        content.addUserScript(WKUserScript(source: WindowMessages.script, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true, in: .page))
        content.addUserScript(WKUserScript(source: Self.vibrantScript, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true, in: .page))
        content.addScriptMessageHandler(services, contentWorld: .page, name: "binahShell")
        content.add(windowMessages, contentWorld: .page, name: "binahWindow")

        let view = ShellWebView(frame: window?.contentView?.bounds ?? .zero, configuration: config)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isInspectable = true                     // Safari → Develop, for a look inside the page
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false   // the page's own back (binahBack)
        view.pageZoom = Zoom.level
        view.underPageBackgroundColor = window?.backgroundColor
        services.webView = view
        webView = view
        // The sidebar's material behind a web view that draws no background of its own: where the
        // page leaves itself transparent (its rail, under .shell-vibrant) the desktop shows through,
        // blurred, as in Finder's or Mail's sidebar; everything it paints covers it.
        let material = NSVisualEffectView(frame: window?.contentView?.bounds ?? .zero)
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        view.frame = material.bounds
        material.addSubview(view)
        window?.contentView = material
        view.load(URLRequest(url: route.map(Server.url) ?? Server.base))
    }

    /// Tells the page the sidebar material is behind it (docs/SHELL.md §9), before its styles apply,
    /// so it can leave its rail transparent from the first frame.
    static let vibrantScript = "document.documentElement.classList.add('shell-vibrant')"

    /// Binah moved (Settings → Address): the page again, from there.
    func loadFromBase() {
        webView.load(URLRequest(url: Server.base))
    }

    /// A route of the page ("#skills"): the page's own go, if Binah is showing, else
    /// the page loaded on it.
    func go(_ route: String) {
        let r = route.hasPrefix("#") ? String(route.dropFirst()) : route
        if let url = webView.url, Server.isOurs(url), !webView.isLoading {
            webView.evaluateJavaScript("window.binahCommand ? window.binahCommand(\(Self.json("go:" + r))) : (location.hash = \(Self.json(r)), true)",
                                       completionHandler: nil)
        } else {
            webView.load(URLRequest(url: Server.url("#" + r)))
        }
    }

    /// View → Reload: the page's own reload, or the address again after an error.
    func reloadPage() {
        guard confirmLosingRecording("Reload") else { return }
        if let url = webView.url, Server.isOurs(url) { webView.reload() } else { loadFromBase() }
    }

    static var version: String { UserAgent.version }

    /// Runs one of the page's commands (docs/SHELL.md §3). `done` hears whether it applied.
    func command(_ name: String, _ done: ((Bool) -> Void)? = nil) {
        Menus.ran.append(name)
        webView.evaluateJavaScript("window.binahCommand ? window.binahCommand(\(Self.json(name))) : false") { result, _ in
            MainActor.assumeIsolated {
                let did = (result as? Bool) ?? ((result as? NSNumber)?.boolValue ?? false)
                if !did && name == "back" { NSSound.beep() }
                done?(did)
            }
        }
    }

    static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]), let s = String(data: data, encoding: .utf8) else { return "null" }
        return String(s.dropFirst().dropLast())
    }

    /// The page moved (WindowMessages): the menus and the title follow.
    fileprivate func pageMoved() {
        guard self === Self.front else { return }
        Menus.refresh { state in
            let titles = ["today": "Today", "practice": "Practice", "skills": "Skills", "golden": "Golden Set",
                          "settings": "Settings", "bench": "Benchmark", "play": "Practice", "gold": "Golden Set"]
            let route = state["route"] as? String ?? ""
            self.window?.title = titles[route].map { "Binah · \($0)" } ?? "Binah"
            if route == "today" { Task { await Today.shared.refresh(soon: true) } }
        }
    }

    // MARK: recording

    /// True while the page records a voice answer (binahShell.mic).
    var recording: Bool { services.recording }

    /// Closing or reloading in the middle of a voice answer loses it: asks first.
    private func confirmLosingRecording(_ verb: String) -> Bool {
        guard recording else { return true }
        let alert = NSAlert()
        alert.messageText = "You're recording an answer"
        alert.informativeText = "\(verb) now and the recording is lost."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: verb)
        return alert.runModal() == .alertSecondButtonReturn
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmLosingRecording("Close") }

    // MARK: the traffic lights

    /// The close, minimise and zoom buttons, in the middle of a 44 px strip rather than
    /// the 28 px title bar they come in. AppKit puts them back whenever it lays the title
    /// bar out again, sometimes with no window event to say so (macOS 26 and later), so
    /// this runs after each of those and whenever a button is moved.
    func layoutTrafficLights() {
        guard !layingOut, let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        layingOut = true
        defer { layingOut = false }
        let height = Self.stripHeight
        var frame = container.frame
        frame.size.height = height
        frame.origin.y = window.frame.height - height
        if container.frame != frame { container.frame = frame }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, kind) in buttons.enumerated() {
            guard let b = window.standardWindowButton(kind) else { continue }
            let at = NSPoint(x: Self.lightsInset + CGFloat(i) * 20, y: ((height - b.frame.height) / 2).rounded())
            if b.frame.origin != at { b.setFrameOrigin(at) }
            watch(b)
        }
    }

    private var layingOut = false
    private var watched: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// When AppKit moves a light back, it goes where it belongs on the next turn of the loop.
    private func watch(_ button: NSView) {
        guard watched[ObjectIdentifier(button)] == nil else { return }
        button.postsFrameChangedNotifications = true
        watched[ObjectIdentifier(button)] = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.layingOut else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.layoutTrafficLights() } }
            }
        }
    }

    func windowDidResize(_ notification: Notification) { layoutTrafficLights() }
    func windowDidEndLiveResize(_ notification: Notification) { layoutTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) {
        layoutTrafficLights()
        tellFullScreen()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { tellFullScreen() }
    func windowDidBecomeKey(_ notification: Notification) {
        layoutTrafficLights()
        pageMoved()
    }
    func windowDidResignKey(_ notification: Notification) { layoutTrafficLights() }

    /// In full screen the traffic lights are gone, and the rail need not leave room for them.
    private func tellFullScreen() {
        let on = window?.styleMask.contains(.fullScreen) ?? false
        webView.evaluateJavaScript("document.documentElement.classList.toggle('shell-fullscreen', \(on))", completionHandler: nil)
    }

    func windowWillClose(_ notification: Notification) {
        for o in watched.values { NotificationCenter.default.removeObserver(o) }
        watched.removeAll()
        services.stopRecordingActivity()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.stopLoading()
        Self.all.removeAll { $0 === self }
    }

    // MARK: moving the window from the page's empty ground

    /// A press on empty ground or in the top strip (WindowMessages.script) moves the
    /// window, as a title bar would; two zoom it, or whatever System Settings → Desktop &
    /// Dock says a double-click on a title bar does.
    fileprivate func windowMessage(_ what: String) {
        if what == "route" { return pageMoved() }
        guard let window, let down = webView.lastMouseDown,
              ProcessInfo.processInfo.systemUptime - down.timestamp < 1 else { return }
        switch what {
        case "drag":
            guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
            window.performDrag(with: down)
            // The drag took the release, which WebKit is still waiting for.
            if NSEvent.pressedMouseButtons & 1 == 0,
               let up = NSEvent.mouseEvent(with: .leftMouseUp, location: window.mouseLocationOutsideOfEventStream,
                                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 0) {
                webView.mouseUp(with: up)
            }
        case "zoom":
            switch UserDefaults(suiteName: UserDefaults.globalDomain)?.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
            case "Minimize": window.miniaturize(nil)
            case "None": break
            default: window.zoom(nil)
            }
        default: break
        }
    }

    // MARK: WKNavigationDelegate

    /// The window only ever shows Binah (docs/SHELL.md §9). A link anywhere else opens in
    /// the browser, or the app it belongs to.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { return decisionHandler(.allow) }
        guard action.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
        if Server.isOurs(target) || target.scheme == "about" || target.scheme == "blob" || target.scheme == "data" {
            return decisionHandler(.allow)
        }
        Outside.open(target)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if window?.styleMask.contains(.fullScreen) == true { tellFullScreen() }
        pageMoved()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   // a download, not a page
        NSLog("Binah: could not open \(Server.base.absoluteString) — \(error.localizedDescription)")
        webView.loadHTMLString(Self.unreachable(Server.base.absoluteString, error.localizedDescription), baseURL: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebKit's page process went away (memory, a crash): bring the page back
        NSLog("Binah: the page's process ended; loading it again")
        services.stopRecordingActivity()
        loadFromBase()
    }

    private static func unreachable(_ place: String, _ why: String) -> String {
        let esc = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        return """
        <!doctype html><meta charset="utf-8"><style>
        body{font:13px -apple-system,sans-serif;color:#575279;background:#ece3d7;display:flex;height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}
        @media (prefers-color-scheme:dark){body{color:#b5bfe2;background:#1b1d2b}}
        h1{font:italic 500 22px Georgia,serif;color:inherit}
        </style><div><h1>Binah couldn't open \(esc(place))</h1><p>\(esc(why))</p>
        <p>View → Reload (⌘R) tries again. Binah → Settings… picks another address.</p></div>
        """
    }

    // MARK: WKUIDelegate

    /// The microphone, for a voice answer (docs/SHELL.md §2): Binah's own page may have
    /// it, nothing else, and never the camera. macOS then asks once whether Binah may.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        let ok = frame.isMainFrame && Server.isOurs(origin) && type == .microphone
        Self.micAnswers.append("\(origin.protocol)://\(origin.host):\(origin.port) \(type == .microphone ? "mic" : "camera") \(ok ? "grant" : "deny")")
        decisionHandler(ok ? .grant : .deny)
    }

    /// What the microphone requests were answered, for the self-test.
    static var micAnswers: [String] = []

    /// window.open and target=_blank: the browser, or for Binah's own pages another window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let target = action.request.url {
            if Server.isOurs(target) { Self.open(target.fragment.map { "#" + $0 }) } else { Outside.open(target) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    /// <input type=file>, should the page ever have one.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let window { panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) } } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    private func present(_ alert: NSAlert, _ done: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { r in MainActor.assumeIsolated { done(r) } }
        } else {
            done(alert.runModal())
        }
    }
}

/// The page tells the window where a press landed, and when it moved
/// (WindowMessages.script). Its own object, held weakly, so the web view's
/// configuration, which keeps its handlers, does not keep the window alive.
final class WindowMessages: NSObject, WKScriptMessageHandler {
    weak var owner: BinahWindowController?
    init(owner: BinahWindowController) { self.owner = owner }

    /// What the pages have asked, for the self-test.
    @MainActor static var received: [String] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let what = message.body as? String else { return }
        MainActor.assumeIsolated {
            Self.received.append(what)
            owner?.windowMessage(what)
        }
    }

    /// A press that isn't on a control, on the page's empty ground (around the column,
    /// the rail below its buttons) or in the top 28 px, moves the window; a second one
    /// zooms it (docs/SHELL.md §9). And the page says when its route changes.
    static let script = """
    (() => {
      const post = (m) => { try { window.webkit.messageHandlers.binahWindow.postMessage(m); } catch (e) {} };
      const CONTROL = 'button, a, input, select, textarea, label, summary, [contenteditable], [role=button], [role=menuitem], [role=tab], [role=slider], [tabindex]';
      const GROUND = 'html, body, #app, #main, .rail, .brand, .brand *';
      window.addEventListener('mousedown', (e) => {
        if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        const t = e.target;
        if (!t || !t.closest || t.closest(CONTROL)) return;
        if (!(e.clientY < 28 || t.matches(GROUND))) return;
        post(e.detail >= 2 ? 'zoom' : 'drag');
      }, true);
      window.addEventListener('hashchange', () => post('route'));
    })();
    """
}

/// Keys with ⌘ or ⌃ go to the menus first, as in any Mac app; the Edit items send
/// copy: and paste: back to the page, so those still reach a text box. Binah's page has
/// no ⌘ keys of its own (its game keys are plain letters and digits), so nothing runs twice.
final class ShellWebView: WKWebView {
    /// The last press, for a drag the page asks for a moment later.
    private(set) var lastMouseDown: NSEvent?

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty,
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Keys go to the page from the moment its window opens.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// The page's presses are the page's; moving the window is asked for.
    override var mouseDownCanMoveWindow: Bool { false }
}

/// View → Zoom In and Out: the page's size, the same in every window, remembered.
@MainActor
enum Zoom {
    static let key = "pageZoom"
    static let steps: [CGFloat] = [0.75, 0.85, 1, 1.1, 1.25, 1.4, 1.6]

    static var level: CGFloat {
        let z = UserDefaults.standard.double(forKey: key)
        return z > 0 ? CGFloat(z) : 1
    }

    static func set(_ z: CGFloat) {
        UserDefaults.standard.set(Double(z), forKey: key)
        for c in BinahWindowController.all { c.webView.pageZoom = z }
    }

    static func bigger() { set(steps.first { $0 > level + 0.001 } ?? level) }
    static func smaller() { set(steps.last { $0 < level - 0.001 } ?? level) }
}

/// The browser, or the app a link belongs to, for anything that isn't Binah. The
/// self-test only notes it.
@MainActor
enum Outside {
    static var opened: [URL] = []
    static var testing: Bool { UserDefaults.standard.string(forKey: "SelfTestOut") != nil }

    /// False for what a link must never open from here: files, scripts.
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !["file", "javascript", "data", "blob", "about"].contains(scheme) else { return false }
        opened.append(url)
        if !testing { NSWorkspace.shared.open(url) }
        return true
    }
}
