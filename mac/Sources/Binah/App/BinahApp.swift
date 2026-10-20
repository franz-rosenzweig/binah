import SwiftUI
import AppKit

/// Binah for Mac: the system's own window, sidebar, toolbar, inspector, tables and Settings
/// window over Binah's JSON API (docs/API.md). Everything is SwiftUI and AppKit; nothing is a web view.
@main
struct BinahApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Binah", id: "main") {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onAppear { delegate.model = model }
                .frame(minWidth: 960, minHeight: 640)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])   // a binah:// link comes to the open window
        }
        .defaultSize(width: 1240, height: 820)
        .commands { BinahCommands(model: model) }

        Settings {
            SettingsWindow().environment(model)
        }

        MenuBarExtra(isInserted: Binding(get: { MenuBarPrefs.shown }, set: { MenuBarPrefs.shown = $0 })) {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar's Go menu and the app's own commands.
struct BinahCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Train on This…") { model.showTrain = true }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!model.signedIn)
        }
        CommandMenu("Go") {
            ForEach(Array(Room.allCases.enumerated()), id: \.element) { i, r in
                Button(r.title) { model.go(r) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                    .disabled(!model.signedIn)
            }
            Divider()
            Button("Back") { model.back() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model.path.isEmpty)
            Button("Reload") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.signedIn)
        }
        CommandGroup(replacing: .help) {
            Link("Binah on GitHub", destination: URL(string: "https://github.com/franz-rosenzweig/binah")!)
        }
    }
}

/// The parts SwiftUI leaves to AppKit: the Services menu's Train on This, and the self-test.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if ProcessInfo.processInfo.environment["BINAH_SELFTEST"] != nil {
            Task { @MainActor in await SelfTest.run(self) }
        }
    }

    /// Closing the last window leaves Binah running; the Dock icon brings one back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Services → Train on This in Binah: the selected text or link, straight to /api/save.
    @objc(trainOnThis:userData:error:)
    func trainOnThis(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let url = (pboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: { !$0.isFileURL })
        guard let s = url?.absoluteString ?? pboard.string(forType: .string), !s.isEmpty else {
            error.pointee = "Nothing to send: select some text or a link." as NSString
            return
        }
        Task { @MainActor in
            let said = await TrainOnThis.send(s)
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = said.ok ? "Sent to Binah" : "Binah didn't take it"
            alert.informativeText = said.message
            alert.runModal()
        }
    }
}
