import AppKit
import WebKit

/// `window.binahShell` (docs/SHELL.md §2): what Binah's page asks of the Mac. Each call is
/// a message with a reply, so the page's promise settles when the Mac is done.
@MainActor
final class ShellServices: NSObject, WKScriptMessageHandlerWithReply, NSSharingServicePickerDelegate {
    weak var webView: WKWebView?
    private var picked: CheckedContinuation<Bool, Never>?
    /// Holds off sleep while a voice answer records (mic).
    private var activity: NSObjectProtocol?
    private(set) var recording = false

    /// What the page has asked, for the self-test: "haptic confirm", "bars #ece3d7 light".
    static var heard: [String] = []

    /// Defined before the page's own scripts run, so the page finds it at once.
    static var script: String {
        """
        (() => {
          const call = (op, args) => window.webkit.messageHandlers.binahShell.postMessage({ op, args: args || {} });
          const ops = ['haptic', 'bars', 'share', 'openExternal', 'mic'];
          const s = v => v == null ? '' : String(v);
          window.binahShell = Object.freeze({
            platform: 'mac', version: \(BinahWindowController.json(UserAgent.version)),
            can: op => ops.includes(op),
            haptic: kind => call('haptic', { kind: s(kind) }),
            bars: o => call('bars', { bg: s(o && o.bg), dark: !!(o && o.dark) }),
            share: o => call('share', { text: s(o && o.text), url: s(o && o.url) }),
            openExternal: url => call('openExternal', { url: s(url) }),
            mic: on => call('mic', { on: !!on }),
          });
        })();
        """
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                           replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        MainActor.assumeIsolated {
            guard message.frameInfo.isMainFrame, let url = webView?.url, Server.isOurs(url) else {
                return replyHandler(nil, "only Binah's own page may use the shell")
            }
            guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
                return replyHandler(nil, "not a shell message")
            }
            let args = body["args"] as? [String: Any] ?? [:]
            Task { @MainActor in
                do { replyHandler(try await self.answer(op, args), nil) } catch { replyHandler(nil, error.localizedDescription) }
            }
        }
    }

    private func answer(_ op: String, _ args: [String: Any]) async throws -> Any {
        let str = { (k: String) in (args[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        switch op {
        case "haptic":
            // felt on a Force Touch trackpad, nowhere else; that's the Mac's whole haptic vocabulary
            let kind = str("kind") ?? "tick"
            Self.heard.append("haptic \(kind)")
            let pattern: NSHapticFeedbackManager.FeedbackPattern = kind == "confirm" ? .levelChange : kind == "reject" ? .generic : .alignment
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            if kind == "reject" {
                // a miss gets a second bump, so it doesn't feel like a right answer
                try? await Task.sleep(nanoseconds: 90_000_000)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            return true
        case "bars":
            // the window's ground, under the transparent title bar and when the page overscrolls
            let dark = (args["dark"] as? Bool) ?? false
            Self.heard.append("bars \(str("bg") ?? "-") \(dark ? "dark" : "light")")
            guard let color = str("bg").flatMap(Self.color), let window = webView?.window else { return true }
            window.backgroundColor = color
            webView?.underPageBackgroundColor = color
            return true
        case "share":
            var items: [Any] = []
            if let u = str("url"), let url = URL(string: u) { items.append(url) }
            if let t = str("text") { items.append(t) }
            Self.heard.append("share \(items.count)")
            guard !items.isEmpty else { return false }
            if Outside.testing { return true }
            return await showShare(items)
        case "openExternal":
            guard let s = str("url"), let url = URL(string: s) else { return false }
            Self.heard.append("openExternal \(s)")
            return Outside.open(url)
        case "mic":
            let on = (args["on"] as? Bool) ?? false
            Self.heard.append("mic \(on)")
            if on { startRecordingActivity() } else { stopRecordingActivity() }
            return true
        default:
            throw ShellError("no such shell call: \(op)")
        }
    }

    /// While a voice answer records: no sleep, no dimmed display, and the window asks
    /// before it closes or reloads (BinahWindowController).
    private func startRecordingActivity() {
        recording = true
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled],
                                                         reason: "Recording a voice answer")
    }

    func stopRecordingActivity() {
        recording = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// "#ece3d7" as a colour; nil for anything else.
    static func color(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// The share picker beside the pointer (the page's Share button was just pressed there).
    /// True once something was picked, false if it was dismissed.
    private func showShare(_ items: [Any]) async -> Bool {
        guard let view = webView, let window = view.window else { return false }
        let at = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picked?.resume(returning: false)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            picked = c
            picker.show(relativeTo: NSRect(x: at.x, y: at.y, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            picked?.resume(returning: service != nil)
            picked = nil
        }
    }
}

struct ShellError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
