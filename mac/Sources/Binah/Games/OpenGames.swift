import SwiftUI

// The games Claude grades against a hidden key: Gist & Infer, Subtext and Cut the Bloat. Each runs
// the same fixed order (OpenFlow): answer with a self-rating → verdict → one revision → reference.

// MARK: Gist & Infer

/// Read the passage at your own pace, hide it, then write its point from memory in 20 words or
/// fewer, and answer one inference question.
struct GistGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var hidden = false
    @State private var gist = ""
    @State private var inference = ""
    @State private var selfRating: Int?
    @State private var flow = OpenFlow()
    @State private var started = Date()
    @FocusState private var focus: Bool

    var body: some View {
        GameColumn {
            if !hidden {
                SourceLine(source: item.source)
                Passage(text: item.passage ?? "")
                VStack(spacing: 6) {
                    Button("I've Got It, Hide the Passage") { withAnimation { hidden = true }; focus = true }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    Text("Read at your own pace. Rereading is fine.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else {
                let n = wordCount(gist)
                Ask(text: "What's the main point? 20 words or fewer, from memory.")
                AnswerBox(label: "Your gist", text: $gist, minHeight: 70, readOnly: flow.locked)
                    .focused($focus)
                HStack {
                    Text("the point, not the topic").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(n) / 20").monospacedDigit().foregroundStyle(n > 20 ? Color.bad : .secondary)
                }
                .font(.callout)
                Ask(text: item.inference_q ?? "")
                AnswerBox(label: "Your answer", text: $inference, minHeight: 60, readOnly: flow.locked)
                if flow.phase == .answering {
                    SelfRating(value: $selfRating)
                    Button("Send to the Grader") {
                        flow.send(item, answer, selfRating: selfRating, started: started, ctx: ctx)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(n == 0 || n > 20 || selfRating == nil)
                } else if flow.phase == .revising {
                    Button("Send the Revision") { flow.reviseAgain(answer) }
                        .buttonStyle(.glassProminent).disabled(n == 0 || n > 20)
                }
                OpenFlowPanel(flow: flow, ctx: ctx, onRevise: { focus = true }) { a in
                    let k = a.key ?? .null
                    let covered = Set(((a.grade2 ?? a.grade)?["covered"]?.array ?? []).compactMap(\.int))
                    Card(title: "The reference") {
                        Text(k["gist"]?.string ?? "").font(.reading(17)).italic()
                        ForEach(Array(k["key_points"]?.strings.enumerated() ?? [].enumerated()), id: \.offset) { i, p in
                            Label(p, systemImage: covered.contains(i + 1) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(covered.contains(i + 1) ? Color.good : .secondary)
                        }
                        if let inf = k["inference_a"]?.string {
                            Text("**The inference:** \(inf)")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) { Text(hidden ? "Write" : "Read").foregroundStyle(.secondary) }
        }
    }

    private var answer: [String: Any] {
        ["gist": gist.trimmingCharacters(in: .whitespacesAndNewlines), "inference": inference.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

// MARK: Subtext

/// What's really going on in a scene: the passage on the left, the question and your answer in the
/// inspector.
struct SubtextGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var text = ""
    @State private var selfRating: Int?
    @State private var flow = OpenFlow()
    @State private var started = Date()

    var body: some View {
        ReadingPane {
            SourceLine(source: item.source)
            Passage(text: item.passage ?? "")
        }
        .answerInspector {
            Ask(text: item.question ?? "")
            AnswerBox(label: "Your answer", text: $text, minHeight: 110, readOnly: flow.locked)
            if flow.phase == .answering {
                SelfRating(value: $selfRating)
                Button("Send to the Grader") {
                    flow.send(item, ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)], selfRating: selfRating, started: started, ctx: ctx)
                }
                .buttonStyle(.glassProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selfRating == nil)
            } else if flow.phase == .revising {
                Button("Send the Revision") { flow.reviseAgain(["text": text.trimmingCharacters(in: .whitespacesAndNewlines)]) }
                    .buttonStyle(.glassProminent)
            }
            OpenFlowPanel(flow: flow, ctx: ctx, onRevise: {}) { a in
                let k = a.key ?? .null
                Card(title: "What's going on") {
                    Text(k["answer"]?.string ?? "")
                    if let q = k["evidence_quote"]?.string, !q.isEmpty {
                        Text("It shows in: “\(q)”").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: Cut the Bloat

/// Someone padded a good writer's sentence; cut it back without changing what it says. Par is the
/// author's own word count, and the score is golf.
struct BloatGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var text = ""
    @State private var selfRating: Int?
    @State private var flow = OpenFlow()
    @State private var started = Date()

    var body: some View {
        let n = wordCount(text), par = item.par ?? 0, d = n - par
        GameColumn {
            SourceLine(source: item.source)
            Ask(text: "Someone padded a good writer's sentence. Cut it back without changing what it says. Par is the author's own word count.")
            AnswerBox(label: "Your cut", text: $text, minHeight: 150, readOnly: flow.locked, font: .reading(17))
            HStack {
                Text("\(n) words · par \(par)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text(golf(d)).fontWeight(.semibold).foregroundStyle(d <= 0 ? Color.good : d > 2 ? Color.bad : .secondary)
            }
            .font(.callout)
            if flow.phase == .answering {
                SelfRating(value: $selfRating)
                Button("Putt") { flow.send(item, ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)], selfRating: selfRating, started: started, ctx: ctx) }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(n == 0 || selfRating == nil)
            } else if flow.phase == .revising {
                Button("Putt Again") { flow.reviseAgain(["text": text.trimmingCharacters(in: .whitespacesAndNewlines)]) }
                    .buttonStyle(.glassProminent)
            }
            OpenFlowPanel(flow: flow, ctx: ctx, onRevise: {}) { a in
                let k = a.key ?? .null
                let ins = a.instant ?? .null
                Card(title: "The author's line · \(par) words") {
                    Text(k["original"]?.string ?? "").font(.reading(17)).italic()
                    if let g = ins["golf"]?.string {
                        Text("You: \(ins["words"]?.int ?? n) words, \(g)").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar { ToolbarItem(placement: .status) { Text("Par \(par)").foregroundStyle(.secondary) } }
        .onAppear { if text.isEmpty { text = item.padded ?? "" } }
    }

    private func golf(_ d: Int) -> String {
        d <= -2 ? "Eagle" : d == -1 ? "Birdie" : d == 0 ? "Par" : d == 1 ? "Bogey" : d == 2 ? "Double bogey" : "+\(d)"
    }
}
