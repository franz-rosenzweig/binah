import AppKit
import ServiceManagement
import SwiftUI
import WebKit

/// Binah → Mac App Settings…: what the Mac app keeps. Binah's own settings stay in the page
/// (Binah → Settings…, ⌘,).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        NSApp.bringForward()
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        w.title = "Binah Mac App Settings"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    /// Makes this Mac's device token with the sign-in in a Binah window (docs/SHELL.md §5),
    /// and keeps it. Nil when it worked, otherwise what to say.
    static func connect() async -> String? {
        guard let c = BinahWindowController.all.first(where: { $0.webView.url.map(Server.isOurs) ?? false }) else {
            BinahWindowController.open()
            return "Sign in to Binah in its window, then press Connect again."
        }
        let js = """
        const r = await fetch('/api/devices', { method: 'POST', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'mac' }) });
        return { status: r.status, body: await r.text() };
        """
        let answer: Any?
        do { answer = try await c.webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) } catch {
            return "Binah didn't answer: \(error.localizedDescription)"
        }
        let a = answer as? [String: Any] ?? [:]
        let status = (a["status"] as? NSNumber)?.intValue ?? 0
        let body = (a["body"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        switch status {
        case 200..<300:
            guard let token = body?["token"] as? String, !token.isEmpty else { return "Binah answered without a token." }
            return Token.set(token) ? nil : "The Keychain didn't take the token."
        case 401: return "Sign in to Binah in its window first, then press Connect again."
        default: return (body?["detail"] as? String) ?? "Binah answered \(status)."
        }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject private var today = Today.shared
    @State private var address = Server.base.absoluteString
    @State private var addressNote: String?
    @State private var pasted = ""
    @State private var tokenNote: String?
    @State private var connecting = false
    @State private var hasToken = Token.value != nil
    @State private var menuBar = MenuBar.shown
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Address", text: $address, prompt: Text(Server.defaultBase))
                        .labelsHidden()
                        .onSubmit(useAddress)
                    Button("Use", action: useAddress).disabled(address == Server.base.absoluteString)
                }
                note(addressNote ?? "https://binah.tiresia.xyz, or a sandbox such as http://localhost:8471. The microphone needs https or localhost.")
            } header: { Text("Binah's address") }

            Section {
                Text(status).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(hasToken ? "Connect Again" : "Connect This Mac") {
                        connecting = true
                        Task {
                            tokenNote = await SettingsWindow.connect()
                            hasToken = Token.value != nil
                            connecting = false
                        }
                    }.disabled(connecting)
                    if hasToken {
                        Button("Forget the Token") { Token.set(nil); hasToken = false; tokenNote = nil }
                    }
                }
                HStack {
                    SecureField("Token", text: $pasted, prompt: Text("Or paste a token")).labelsHidden()
                    Button("Save") {
                        tokenNote = Token.set(pasted) ? nil : "The Keychain didn't take the token."
                        pasted = ""
                        hasToken = Token.value != nil
                    }.disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                note(tokenNote ?? "The menu bar and Train on This use a device token, kept in the Keychain. Connect makes one with your sign-in in the Binah window; Binah's Settings lists it as \"mac\".")
            } header: { Text("This Mac") }

            Section {
                Toggle("Show today's edition in the menu bar", isOn: $menuBar)
                    .onChange(of: menuBar) { _, on in
                        UserDefaults.standard.set(on, forKey: MenuBar.shownKey)
                        if on { MenuBar.shared.install() } else { MenuBar.shared.remove() }
                    }
                Toggle("Open Binah at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {
                            NSLog("Binah: login item: \(error.localizedDescription)")
                        }
                        atLogin = SMAppService.mainApp.status == .enabled
                    }
                note("At login Binah starts in the menu bar, without a window.")
            } header: { Text("Menu bar") }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private var status: String {
        if !hasToken { return "Not connected yet." }
        if let w = today.widget, !today.stale { return "Connected. " + (w.finished ? "Today's edition is done." : today.line + ".") }
        if let p = today.problem { return p }
        return "Connected."
    }

    private func useAddress() {
        let typed = address.trimmingCharacters(in: .whitespaces)
        if Server.setBase(typed.isEmpty ? Server.defaultBase : typed) {
            address = Server.base.absoluteString
            addressNote = nil
        } else {
            addressNote = "That isn't an address Binah can use. It starts with https:// or http://."
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
