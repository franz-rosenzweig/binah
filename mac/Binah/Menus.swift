import AppKit

/// The menu bar. Each Binah item calls the page's own command (`window.binahCommand`,
/// docs/SHELL.md §3) in the window in front; what's greyed and ticked comes from
/// `window.binahState()`, asked when a menu opens and whenever the page moves.
///
/// ⌘, is the page's own Settings (the weekly goal, how Claude talks to you), because
/// that's what a person means by Binah's settings; what the Mac app keeps (the address,
/// the connection, the menu bar) is Mac App Settings…, ⌥⌘,.
@MainActor
enum Menus {
    /// What the page in front said last (binahState).
    static var state: [String: Any] = [:]
    /// The page's commands run, from the menus or elsewhere, for the self-test.
    static var ran: [String] = []

    static var signedIn: Bool { (state["signedIn"] as? Bool) ?? ((state["signedIn"] as? NSNumber)?.boolValue ?? false) }
    static var route: String { state["route"] as? String ?? "" }
    static var canBack: Bool { (state["canBack"] as? Bool) ?? ((state["canBack"] as? NSNumber)?.boolValue ?? false) }

    /// Asks the page in front for its state, then shows it in whatever menu is open.
    static func refresh(_ menu: NSMenu? = nil, _ done: (([String: Any]) -> Void)? = nil) {
        guard let web = BinahWindowController.front?.webView else { state = [:]; return }
        web.evaluateJavaScript("window.binahState ? window.binahState() : null") { result, _ in
            MainActor.assumeIsolated {
                state = (result as? [String: Any]) ?? [:]
                menu?.update()
                done?(state)
            }
        }
    }

    static func build() -> NSMenu {
        let bar = NSMenu(title: "Main Menu")
        for m in [appMenu(), fileMenu(), editMenu(), viewMenu(), goMenu()] {
            m.delegate = Opening.shared
            bar.addItem(submenu(m))
        }
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bar.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        help.addItem(shell("Binah on GitHub", #selector(MenuTarget.github(_:))))
        bar.addItem(submenu(help))
        NSApp.helpMenu = help
        return bar
    }

    // MARK: the menus

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "Binah")
        m.addItem(withTitle: "About Binah", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(item("Settings…", "go:settings", ","))
        m.addItem(shell("Mac App Settings…", #selector(MenuTarget.settings(_:)), ",", [.command, .option]))
        m.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        m.addItem(services)
        m.addItem(.separator())
        m.addItem(withTitle: "Hide Binah", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = m.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        m.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Binah", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "File")
        m.addItem(shell("New Window", #selector(MenuTarget.newWindow(_:)), "n"))
        m.addItem(.separator())
        m.addItem(shell("Train on This…", #selector(MenuTarget.trainOnThis(_:)), "t", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: "Edit")
        m.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = m.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        m.addItem(.separator())
        m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = m.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        m.addItem(.separator())
        // the system's spelling, in the answers you write; WebKit answers these itself
        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spelling.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spelling.addItem(.separator())
        spelling.addItem(withTitle: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        spelling.addItem(withTitle: "Check Grammar With Spelling", action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: "")
        m.addItem(submenu(spelling))
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "View")
        m.addItem(shell("Reload", #selector(MenuTarget.reload(_:)), "r"))
        m.addItem(.separator())
        m.addItem(shell("Actual Size", #selector(MenuTarget.actualSize(_:)), "0"))
        m.addItem(shell("Zoom In", #selector(MenuTarget.zoomIn(_:)), "+"))
        // ⌘= too, as in Safari, without a second line in the menu
        let plus = shell("Zoom In", #selector(MenuTarget.zoomIn(_:)), "=")
        plus.isHidden = true
        plus.allowsKeyEquivalentWhenHidden = true
        m.addItem(plus)
        m.addItem(shell("Zoom Out", #selector(MenuTarget.zoomOut(_:)), "-"))
        m.addItem(.separator())
        let full = m.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        return m
    }

    private static func goMenu() -> NSMenu {
        let m = NSMenu(title: "Go")
        for (i, (title, route)) in [("Today", "today"), ("Practice", "practice"), ("Skills", "skills"),
                                    ("Golden Set", "golden"), ("Benchmark", "bench")].enumerated() {
            m.addItem(item(title, "go:" + route, String(i + 1)))
        }
        m.addItem(.separator())
        m.addItem(item("Back", "back", "["))
        return m
    }

    // MARK: making items

    private static func submenu(_ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        i.submenu = m
        return i
    }

    /// An item that runs one of the page's commands.
    private static func item(_ title: String, _ command: String, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = PageItem(title: title, action: #selector(MenuTarget.run(_:)), keyEquivalent: key)
        i.command = command
        i.keyEquivalentModifierMask = mods
        i.target = MenuTarget.shared
        return i
    }

    /// An item the Mac app answers itself.
    private static func shell(_ title: String, _ action: Selector, _ key: String = "",
                              _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = MenuTarget.shared
        return i
    }
}

/// A menu item for one of the page's commands ("go:practice", "back").
final class PageItem: NSMenuItem {
    var command = ""
}

/// Asks the page for its state as a menu opens, so the menu shows the page as it is.
@MainActor
final class Opening: NSObject, NSMenuDelegate {
    static let shared = Opening()
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { Menus.refresh(menu) }
    }
}

/// What the items call.
@MainActor
final class MenuTarget: NSObject, NSMenuItemValidation {
    static let shared = MenuTarget()

    @objc func run(_ sender: NSMenuItem) {
        guard let item = sender as? PageItem else { return }
        guard let c = BinahWindowController.front else {
            // no window: open one on the place asked for
            if item.command.hasPrefix("go:") { BinahWindowController.open("#" + item.command.dropFirst(3)) }
            return
        }
        c.window?.makeKeyAndOrderFront(nil)
        c.command(item.command)
    }

    @objc func newWindow(_ sender: Any?) { BinahWindowController.open() }
    @objc func settings(_ sender: Any?) { SettingsWindow.show() }
    @objc func trainOnThis(_ sender: Any?) { TrainOnThis.ask() }
    @objc func reload(_ sender: Any?) { BinahWindowController.front?.reloadPage() }
    @objc func actualSize(_ sender: Any?) { Zoom.set(1) }
    @objc func zoomIn(_ sender: Any?) { Zoom.bigger() }
    @objc func zoomOut(_ sender: Any?) { Zoom.smaller() }
    @objc func github(_ sender: Any?) { Outside.open(URL(string: "https://github.com/franz-rosenzweig/binah")!) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let item = menuItem as? PageItem {
            let windowOpen = BinahWindowController.front != nil
            let target = item.command.hasPrefix("go:") ? String(item.command.dropFirst(3)) : ""
            // the place you're at is ticked; a game counts as its section, as the rail shows it
            let section = ["play": "practice", "gold": "golden"][Menus.route] ?? Menus.route
            item.state = windowOpen && !target.isEmpty && target == section ? .on : .off
            if !windowOpen { return item.command.hasPrefix("go:") }
            if item.command == "back" { return Menus.signedIn && Menus.canBack }
            return Menus.signedIn
        }
        switch menuItem.action {
        case #selector(reload(_:)): return BinahWindowController.front != nil
        case #selector(actualSize(_:)): return abs(Zoom.level - 1) > 0.001
        case #selector(zoomIn(_:)): return Zoom.level < (Zoom.steps.last ?? 2) - 0.001
        case #selector(zoomOut(_:)): return Zoom.level > (Zoom.steps.first ?? 0.5) + 0.001
        default: return true
        }
    }
}
