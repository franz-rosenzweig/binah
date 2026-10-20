import SwiftUI
import AppKit

/// Train on this (docs/SHELL.md §7): a link or a passage, kept by Binah for later practice. From
/// File → Train on This… (⇧⌘T), the menu bar, or Services → Train on This in Binah.
enum TrainOnThis {
    /// The text as a link, if all it is is one.
    static func link(_ s: String) -> URL? {
        guard !s.contains(where: \.isWhitespace), let u = URL(string: s),
              ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        return u
    }

    /// A link, or enough words to be a passage: worth offering from the clipboard.
    static func worthOffering(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return link(t) != nil || wordCount(t) >= 20
    }

    /// Sends it, and answers what Binah said.
    @MainActor
    static func send(_ raw: String, title: String? = nil) async -> (ok: Bool, message: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return (false, "Nothing to send.") }
        var body: [String: Any] = [:]
        if let u = link(s) { body["url"] = u.absoluteString } else { body["text"] = s }
        if let title, !title.isEmpty { body["title"] = title }
        do {
            let r: Saved = try await API.post("/api/save", body)
            return (true, r.message ?? "Saved.")
        } catch { return (false, error.localizedDescription) }
    }
}

struct TrainOnThisSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var said: (ok: Bool, message: String)?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Train on This").font(.title2.weight(.semibold))
            Text("A link, or a paragraph or more of text. Binah keeps it for practice.").foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.reading(15))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(width: 460, height: 160)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
            if let said {
                Label(said.message, systemImage: said.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(said.ok ? Color.good : Color.bad)
            }
            HStack {
                Spacer()
                Button(said?.ok == true ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if said?.ok != true {
                    Button(busy ? "Sending…" : "Send to Binah") {
                        busy = true
                        Task {
                            said = await TrainOnThis.send(text)
                            busy = false
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string), TrainOnThis.worthOffering(clip) { text = clip }
        }
    }
}
