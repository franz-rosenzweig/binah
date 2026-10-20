import SwiftUI
import AppKit

/// Whether today's edition shows in the menu bar. Off while the web-view Binah app shows its own;
/// on once this app replaces it.
enum MenuBarPrefs {
    static let key = "menuBarShown"
    static var shown: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The menu bar's title: today's games, `1/3`, or `3/3 ✓` once the edition is done, and ב before
/// Binah has answered.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.nav?.today, t.total > 0 {
            Text("\(t.done)/\(t.total)" + (t.done >= t.total ? " ✓" : "")).monospacedDigit()
        } else {
            Text("ב")
        }
    }
}

/// The menu bar's panel: the edition as dots, what's next, the week, and a few commands.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = model.today {
                let ed = t.edition
                HStack(spacing: 6) {
                    ForEach(ed.slots) { s in Circle().fill(s.done ? Color.binah : Color.secondary.opacity(0.3)).frame(width: 10, height: 10) }
                    if ed.finished { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.binah) }
                }
                Text(ed.finished ? "Today's edition is done." : "\(ed.done) of \(ed.slots.count) games · about \(max(1, ed.minutesLeft)) minutes left")
                    .font(.headline)
                if let n = ed.next, !ed.finished { Text("Next: \(n.name ?? Games.name(n.game))") }
                Text("This week: \(t.week.active) of \(t.week.goal) days").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.signedIn ? "Binah" : "Sign in to Binah in its window.").font(.headline)
            }
            Divider()
            Group {
                Button(model.today?.edition.finished == false ? "Play Today's Edition" : "Open Binah") {
                    show()
                    if let t = model.today, let n = t.edition.next { model.go(.today); model.play(n, day: t.edition.day) }
                }
                Button("Practice") { show(); model.go(.practice) }
                Button("Train on This…") { show(); model.showTrain = true }
                Divider()
                Button("Settings…") { NSApp.activate(); openSettings() }
                Button("Quit Binah") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .tint(Color.binah)
        .task { await model.refresh() }
    }

    private func show() {
        NSApp.activate()
        if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) {
            openWindow(id: "main")
        }
    }
}
