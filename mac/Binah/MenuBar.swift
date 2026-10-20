import AppKit
import SwiftUI

/// Today's edition, from /api/widget with the device token (docs/SHELL.md §6). Asked
/// gently: when the menu opens, at most every 15 minutes in the background, on wake, and
/// once when Binah comes to the front. The last answer is kept, so offline the menu bar
/// shows what it last knew.
@MainActor
final class Today: ObservableObject {
    static let shared = Today()

    @Published private(set) var widget: Client.Widget?
    /// When the server last answered.
    @Published private(set) var at: Date?
    /// Why the last ask failed, if it did.
    @Published private(set) var problem: String?
    @Published private(set) var noToken = false

    private var timer: Timer?
    private var asking = false
    private var askedAt: Date?
    private static let keptKey = "widget.last", keptAtKey = "widget.at"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.keptKey) {
            widget = try? JSONDecoder().decode(Client.Widget.self, from: data)
            at = UserDefaults.standard.object(forKey: Self.keptAtKey) as? Date
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            Task { @MainActor in await Today.shared.refresh() }
        }
        timer?.tolerance = 60
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)   // the network comes back a moment after the screen
                    await Today.shared.refresh(soon: true)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await Today.shared.refresh(soon: true) }
        }
        for name in [Notification.Name.binahBaseChanged, .binahTokenChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in await Today.shared.refresh() }
            }
        }
        Task { await refresh() }
    }

    /// Asks the server. `soon`: unless it was asked in the last minute.
    func refresh(soon: Bool = false) async {
        if soon, let askedAt, Date().timeIntervalSince(askedAt) < 60 { return }
        guard !asking else { return }
        asking = true
        askedAt = Date()
        defer { asking = false }
        do {
            let w = try await Client.widget()
            widget = w
            at = Date()
            problem = nil
            noToken = false
            if let data = try? JSONEncoder().encode(w) {
                UserDefaults.standard.set(data, forKey: Self.keptKey)
                UserDefaults.standard.set(at, forKey: Self.keptAtKey)
            }
        } catch Client.Failure.noToken {
            noToken = true
            problem = nil
        } catch {
            noToken = false
            problem = error.localizedDescription
        }
        MenuBar.shared.update()
    }

    /// The last answer is old: more than 20 minutes, or from another day.
    var stale: Bool {
        guard let at else { return true }
        return Date().timeIntervalSince(at) > 1200 || !Calendar.current.isDateInToday(at)
    }

    /// The edition as one line: "1 of 3 games · about 4 minutes left".
    var line: String {
        guard let w = widget else { return "Binah" }
        if w.finished { return "Today's edition is done." }
        let left = w.minutes_left.map { Int($0.rounded()) }.flatMap { $0 > 0 ? " · about \($0) minute\($0 == 1 ? "" : "s") left" : nil } ?? ""
        return "\(w.done) of \(w.total) games\(left)"
    }
}

/// The menu-bar item: today's edition as `1/3`, or `3/3 ✓` once it's done, and ב until
/// Binah has answered. Clicking it shows the edition and a few commands.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    static let shared = MenuBar()
    static let shownKey = "menuBarShown"

    private(set) var item: NSStatusItem?
    /// The menu's top while it's open, to fit it again when a fresh answer arrives.
    private weak var header: NSView?
    /// A word in place of the count for a moment ("Saved").
    private var flashText: String?

    static var shown: Bool {
        UserDefaults.standard.object(forKey: shownKey) == nil || UserDefaults.standard.bool(forKey: shownKey)
    }

    func install() {
        guard Self.shown, item == nil else { return update() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Binah today"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        update()
    }

    func remove() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    /// The title, from what Today knows.
    var title: String {
        if let flashText { return flashText }
        guard let w = Today.shared.widget, !Today.shared.noToken else { return "ב" }
        return "\(w.done)/\(w.total)" + (w.finished ? " ✓" : "")
    }

    func update() {
        guard let button = item?.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = title
        button.appearsDisabled = flashText == nil && Today.shared.widget != nil && Today.shared.stale
        if let header { header.frame.size = header.fittingSize }
        button.toolTip = "Binah: " + Today.shared.line
    }

    /// A word in the menu bar for a few seconds: "Saved".
    func flash(_ text: String) {
        flashText = text
        update()
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            flashText = nil
            update()
        }
    }

    // MARK: the menu

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            fill(menu)
            Task { await Today.shared.refresh(soon: true) }
        }
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem()
        let host = NSHostingView(rootView: TodayHeader(today: Today.shared))
        host.frame.size = host.fittingSize
        header.view = host
        self.header = host
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(action(Today.shared.widget?.finished == false ? "Play Today's Edition" : "Open Binah", #selector(openToday)))
        menu.addItem(action("Practice", #selector(openPractice)))
        menu.addItem(.separator())
        menu.addItem(action("Train on This…", #selector(trainOnThis)))
        menu.addItem(.separator())
        menu.addItem(action("Mac App Settings…", #selector(settings)))
        menu.addItem(action("Quit Binah", #selector(quit)))
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc func openToday() { BinahWindowController.show("#today") }
    @objc func openPractice() { BinahWindowController.show("#practice") }
    @objc func trainOnThis() { TrainOnThis.ask() }
    @objc func settings() { SettingsWindow.show() }
    @objc func quit() { NSApp.terminate(nil) }
}

/// The top of the menu: the edition's games as dots, what's next, and the week.
@MainActor
struct TodayHeader: View {
    @ObservedObject var today: Today

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let w = today.widget, !today.noToken {
                HStack(spacing: 6) {
                    ForEach(0..<max(w.total, 0), id: \.self) { i in
                        Circle()
                            .fill(i < w.done ? Self.teal : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: 10)
                    }
                    if w.finished {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Self.teal)
                    }
                }
                Text(today.line).font(.system(size: 13, weight: .semibold))
                if let next = w.next, !w.finished {
                    Text("Next: \(next.name)").font(.system(size: 12))
                }
                if let week = w.week {
                    Text("This week: \(week.active) of \(week.goal) days").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("Binah").font(.system(size: 13, weight: .semibold))
            }
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 280, alignment: .leading)
    }

    /// Said when there's something to say: not connected yet, or offline.
    private var note: String? {
        if today.noToken { return "Connect this Mac in Mac App Settings to see today's edition here." }
        guard today.problem != nil || (today.widget != nil && today.stale) else { return nil }
        let when = today.at.map { "as of " + $0.formatted(date: Calendar.current.isDateInToday($0) ? .omitted : .abbreviated, time: .shortened) }
        return [today.problem == nil ? "Offline" : today.problem, when].compactMap { $0 }.joined(separator: ", ")
    }

    /// Binah's teal (style.css --accent), lighter on a dark menu.
    static let teal = Color(nsColor: NSColor(name: nil) { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x85 / 255.0, green: 0xc1 / 255.0, blue: 0xdc / 255.0, alpha: 1)
            : NSColor(srgbRed: 0x12 / 255.0, green: 0x61 / 255.0, blue: 0x7f / 255.0, alpha: 1)
    })
}
