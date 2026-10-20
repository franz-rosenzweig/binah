import SwiftUI

/// The golden set: answer an item yourself, see the key, then score your own answer with the same
/// anchors Claude uses. Claude grades the same answer blind in the background (docs/API.md).
struct GoldenPlay: View {
    @Environment(AppModel.self) private var model
    let itemID: String
    @State private var item: Item?
    @State private var rubric: Rubric?
    @State private var problem: String?
    @State private var hidden = false
    @State private var a1 = ""
    @State private var a2 = ""
    @State private var key: JSONValue?
    @State private var mine: [String: Int] = [:]
    @State private var saved = false
    @State private var busy = false

    var body: some View {
        GameColumn {
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            if let item, let rubric {
                answerSide(item)
                if let key { scoring(item, rubric, key) }
            } else if problem == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Golden Set · " + Games.name(item?.game ?? String(itemID.split(separator: ":").first ?? "")))
        .navigationSubtitle("Score your own answer")
        .task {
            do {
                async let i: Item = API.get("/api/item/\(API.escape(itemID))")
                async let g: GoldenInfo = API.get("/api/golden")
                let (it, gi) = try await (i, g)
                item = it
                rubric = gi.rubrics[it.game]
                if it.game == "bloat" { a1 = it.padded ?? "" }
            } catch { problem = error.localizedDescription }
        }
    }

    @ViewBuilder private func answerSide(_ item: Item) -> some View {
        let locked = key != nil
        switch item.game {
        case "gist":
            if !hidden {
                SourceLine(source: item.source)
                Passage(text: item.passage ?? "")
                Button("Hide It and Write") { withAnimation { hidden = true } }.buttonStyle(.glassProminent).controlSize(.large)
            } else {
                Ask(text: "The main point, 20 words or fewer.")
                AnswerBox(label: "Your gist", text: $a1, minHeight: 70, readOnly: locked)
                Ask(text: item.inference_q ?? "")
                AnswerBox(label: "Your answer", text: $a2, minHeight: 60, readOnly: locked)
                if !locked { scoreButton }
            }
        case "subtext":
            SourceLine(source: item.source)
            Passage(text: item.passage ?? "")
            Ask(text: item.question ?? "")
            AnswerBox(label: "Your answer", text: $a1, minHeight: 100, readOnly: locked)
            if !locked { scoreButton }
        default:
            Ask(text: "Cut it back to the author's line (par \(item.par ?? 0)).")
            AnswerBox(label: "Your cut", text: $a1, minHeight: 130, readOnly: locked, font: .reading(17))
            if !locked { scoreButton }
        }
    }

    private var scoreButton: some View {
        Button("Now Score It Yourself") {
            guard !a1.trimmingCharacters(in: .whitespaces).isEmpty || !a2.trimmingCharacters(in: .whitespaces).isEmpty else {
                model.flash("Write an answer first")
                return
            }
            Task {
                do { key = (try await API.get("/api/golden/key/\(API.escape(itemID))", as: GoldenKey.self)).key }
                catch { problem = error.localizedDescription }
            }
        }
        .buttonStyle(.glassProminent).controlSize(.large)
    }

    @ViewBuilder private func scoring(_ item: Item, _ rubric: Rubric, _ k: JSONValue) -> some View {
        if item.game == "gist" {
            DisclosureGroup("The passage again") { Passage(text: item.passage ?? "", size: 15).padding(.top, 6) }
        }
        Card(title: "The key") {
            Text(k["gist"]?.string ?? k["answer"]?.string ?? k["original"]?.string ?? "").font(.reading(17)).italic()
            ForEach(k["key_points"]?.strings ?? [], id: \.self) { p in Label(p, systemImage: "circle.fill").labelStyle(BulletStyle()) }
            if let inf = k["inference_a"]?.string { Text("**Inference:** \(inf)") }
        }
        if saved {
            Card {
                Text("Saved to the golden set").font(.title3.weight(.semibold))
                Text("Claude grades your answer blind in the background, and the agreement report updates.").foregroundStyle(.secondary)
            }
            Button("Back to the Golden Set") { model.go(.golden) }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
        } else {
            Text("Score your own answer the way a strict, fair editor would. These are the same anchors Claude uses.")
                .foregroundStyle(.secondary)
            ForEach(rubric.ordered, id: \.self) { c in
                let levels = rubric.criteria[c] ?? []
                VStack(alignment: .leading, spacing: 6) {
                    Text(CriteriaOrder.label(c).capitalizedFirst).fontWeight(.semibold)
                    Picker(c, selection: Binding(get: { mine[c] ?? -1 }, set: { mine[c] = $0 })) {
                        ForEach(0..<levels.count, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(mine[c].map { "\($0): \(levels[$0])" } ?? "Pick a score to see what it means.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
            }
            Button(busy ? "Saving…" : "Save to the Golden Set", action: save)
                .buttonStyle(.glassProminent)
                .disabled(busy || mine.count < rubric.criteria.count)
        }
    }

    private func save() {
        guard let item else { return }
        busy = true
        let answer: [String: Any] = item.game == "gist"
            ? ["gist": a1.trimmingCharacters(in: .whitespacesAndNewlines), "inference": a2.trimmingCharacters(in: .whitespacesAndNewlines)]
            : ["text": a1.trimmingCharacters(in: .whitespacesAndNewlines)]
        Task {
            do {
                let _: JSONValue = try await API.post("/api/golden", ["item_id": item.id, "answer": answer, "mine": mine])
                saved = true
                await model.refreshNav()
            } catch { problem = error.localizedDescription }
            busy = false
        }
    }
}
