import AppKit

/// Binah for macOS: the live site (docs/SHELL.md) in a window in Moshe's look, with Binah's
/// menus, today's edition in the menu bar, and Train on This in the Services menu.
/// Everything a person plays is the page; this adds what a page can't do.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Opened by a link (binah://go/…): that window instead of the usual one.
    private var openedForLink = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menus.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
        Today.shared.start()
        MenuBar.shared.install()
        NotificationCenter.default.addObserver(forName: .binahBaseChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                for c in BinahWindowController.all { c.loadFromBase() }
            }
        }
        // At login Binah starts in the menu bar only; otherwise a window, unless a link
        // asked for one of its own (the URL arrives a moment after launch).
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launch?.eventID == AEEventID(kAEOpenApplication)
            && launch?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if atLogin { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                if !self.openedForLink && BinahWindowController.all.isEmpty {
                    BinahWindowController.open()
                    NSApp.bringForward()
                }
            }
        }
    }

    /// binah://go/<route> (docs/SHELL.md §8): that page, in the window in front.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "binah" {
            guard url.host?.lowercased() == "go" else { continue }
            let route = url.pathComponents.dropFirst().joined(separator: "/")
            openedForLink = true
            BinahWindowController.show("#" + (route.isEmpty ? "today" : route))
        }
    }

    /// Closing the last window leaves Binah in the menu bar; the Dock icon brings a window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !BinahWindowController.all.contains(where: { $0.window?.isVisible == true }) {
            if let c = BinahWindowController.all.first { c.window?.makeKeyAndOrderFront(nil) } else { BinahWindowController.open() }
        }
        return true
    }

    /// Quitting in the middle of a voice answer loses it: asks first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard BinahWindowController.all.contains(where: \.recording) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You're recording an answer"
        alert.informativeText = "Quit now and the recording is lost."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

extension NSApplication {
    /// Comes to the front. From macOS 14 the system has the last word, as it should.
    func bringForward() { activate() }
}
