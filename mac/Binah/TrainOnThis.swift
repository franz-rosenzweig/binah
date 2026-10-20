import AppKit
import WebKit

/// Train on this (docs/SHELL.md §7): a link or a passage, sent to Binah, which turns it into
/// practice items in the next nightly run. From File → Train on This… (⇧⌘T), the menu bar,
/// or Services → Train on This in Binah with text or a link selected in any app.
@MainActor
enum TrainOnThis {
    /// What was sent and what Binah said, for the self-test.
    static var sent: [String] = []

    /// A box to paste into, filled from the clipboard when it holds a link or a passage.
    static func ask() {
        NSApp.bringForward()
        let alert = NSAlert()
        alert.messageText = "Train on This"
        alert.informativeText = "Paste a link, or a paragraph or more of text. It becomes practice items in the next nightly run."
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 140)
        scroll.borderType = .bezelBorder
        let text = scroll.documentView as! NSTextView
        text.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        if let clip = NSPasteboard.general.string(forType: .string), worthOffering(clip) {
            text.string = clip
            text.selectAll(nil)
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await send(text.string, title: nil) }
    }

    /// A link, or enough words to be a passage.
    private static func worthOffering(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return link(t) != nil || t.split(whereSeparator: \.isWhitespace).count >= 20
    }

    /// The text as a link, if all it is is one.
    private static func link(_ s: String) -> URL? {
        guard !s.contains(where: \.isWhitespace), let u = URL(string: s),
              ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        return u
    }

    /// Sends it with the device token, or with a window's sign-in if this Mac isn't connected
    /// yet, and says what Binah said.
    static func send(_ raw: String, title: String?) async {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let url = link(s)?.absoluteString
        let text = url == nil ? s : nil
        let said: String
        var ok = false
        do {
            if Token.value != nil {
                said = try await Client.save(url: url, text: text, title: title)
            } else {
                said = try await withWindow(url: url, text: text, title: title)
            }
            ok = true
        } catch {
            said = error.localizedDescription
        }
        sent.append((ok ? "ok " : "no ") + said)
        if Outside.testing { return }
        if ok { MenuBar.shared.flash("Saved") }
        let alert = NSAlert()
        alert.messageText = ok ? "Sent to Binah" : "Binah didn't take it"
        alert.informativeText = said
        alert.addButton(withTitle: "OK")
        if ok { alert.addButton(withTitle: "Open Binah") }
        NSApp.bringForward()
        if alert.runModal() == .alertSecondButtonReturn { BinahWindowController.show("#today") }
    }

    /// POST /api/save from a Binah window, with its cookie.
    private static func withWindow(url: String?, text: String?, title: String?) async throws -> String {
        guard let c = BinahWindowController.all.first(where: { $0.webView.url.map(Server.isOurs) ?? false }) else {
            throw ShellError("Open Binah and sign in, or connect this Mac in Mac App Settings.")
        }
        var body: [String: String] = [:]
        if let url { body["url"] = url }
        if let text { body["text"] = text }
        if let title, !title.isEmpty { body["title"] = title }
        let js = """
        const r = await fetch('/api/save', { method: 'POST', credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        let j = {}; try { j = await r.json(); } catch (e) {}
        return { status: r.status, message: j.message || j.detail || '' };
        """
        let a = try await c.webView.callAsyncJavaScript(js, arguments: ["body": body], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        let status = (a["status"] as? NSNumber)?.intValue ?? 0
        let message = a["message"] as? String ?? ""
        guard (200..<300).contains(status) else {
            throw ShellError(status == 401 ? "Sign in to Binah first." : message.isEmpty ? "Binah answered \(status)." : message)
        }
        return message.isEmpty ? "Saved." : message
    }
}

/// Services → Train on This in Binah (NSServices in project.yml).
@MainActor
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    @objc(trainOnThis:userData:error:)
    func trainOnThis(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let url = (pboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: { !$0.isFileURL })
        guard let s = url?.absoluteString ?? pboard.string(forType: .string), !s.isEmpty else {
            error.pointee = "Nothing to send: select some text or a link." as NSString
            return
        }
        Task { await TrainOnThis.send(s, title: nil) }
    }
}
