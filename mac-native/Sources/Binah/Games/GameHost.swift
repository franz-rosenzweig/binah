import SwiftUI

/// Where a game was opened from: one of today's slots (it counts for today) or Practice.
struct PlayContext {
    let game: String
    let day: String?
    let slot: Int?
    let screen: Screen
    var fromToday: Bool { day != nil }

    @MainActor func subtitle(_ model: AppModel) -> String {
        let p = Pillar.name(Games.pillar[game] ?? "")
        let n = model.today?.edition.slots.count ?? 3
        let where_ = fromToday ? "game \((slot ?? 0) + 1) of \(n) in today's edition" : "Practice"
        return p.isEmpty ? where_ : "\(p) · \(where_)"
    }

    var nextTitle: String { fromToday ? "Back to Today" : "Another One" }
}

/// One game on screen: loads its item, then the game's own view.
struct GameView: View {
    @Environment(AppModel.self) private var model
    let game: String
    let ids: [String]
    let day: String?
    let slot: Int?
    let screen: Screen
    @State private var item: Item?
    @State private var problem: String?

    var body: some View {
        let ctx = PlayContext(game: game, day: day, slot: slot, screen: screen)
        Group {
            if game == "tech" {
                TechRound(ids: ids, ctx: ctx)
            } else if let item {
                switch game {
                case "gist": GistGame(item: item, ctx: ctx)
                case "subtext": SubtextGame(item: item, ctx: ctx)
                case "bloat": BloatGame(item: item, ctx: ctx)
                case "weak": WeakGame(item: item, ctx: ctx)
                case "word": WordGame(item: item, ctx: ctx)
                case "jam": JamGame(item: item, ctx: ctx)
                default: ContentUnavailableView("Not a game this app knows", systemImage: "questionmark.square")
                }
            } else if let problem {
                ContentUnavailableView("Couldn't open it", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Games.name(game))
        .navigationSubtitle(ctx.subtitle(model))
        .task(id: ids.first) {
            guard game != "tech", let id = ids.first else { return }
            do { item = try await API.get("/api/item/\(API.escape(id))") } catch { problem = error.localizedDescription }
        }
    }
}

/// POST /api/attempts, with the day and slot when the game is one of today's.
@MainActor
func submitAnswer(_ item: Item, _ answer: [String: Any], selfRating: Int?, started: Date, ctx: PlayContext) async throws -> Attempt {
    var body: [String: Any] = ["item_id": item.id, "answer": answer, "ms": Int(Date().timeIntervalSince(started) * 1000)]
    body["self_rating"] = selfRating ?? NSNull()
    body["day"] = ctx.day ?? NSNull()
    body["slot"] = ctx.slot ?? NSNull()
    return try await API.post("/api/attempts", body)
}

/// The fixed order of an open answer (gist, subtext, bloat): answer with a self-rating → Claude's
/// verdict → one revision → the reference. "Later" (the daily cap, or an error) is final for now:
/// no invented score, and the reference on request (docs/API.md, Answering).
@MainActor @Observable
final class OpenFlow {
    enum Phase { case answering, grading, verdict, revising, regrading, reference, later }
    var phase: Phase = .answering
    var attempt: Attempt?
    var problem: String?
    var disputed = false
    var revised: Bool { attempt?.grade2 != nil }

    var locked: Bool { phase != .answering && phase != .revising }

    func send(_ item: Item, _ answer: [String: Any], selfRating: Int?, started: Date, ctx: PlayContext) {
        phase = .grading
        problem = nil
        Task {
            do {
                let a0 = try await submitAnswer(item, answer, selfRating: selfRating, started: started, ctx: ctx)
                attempt = a0
                let a = a0.grading ? try await API.wait(for: a0.id) { !$0.grading || $0.waitsForTomorrow } : a0
                attempt = a
                if a.later || (a.grade == nil && a.waitsForTomorrow) { phase = .later } else {
                    phase = .verdict
                    (a.score ?? 0) >= 0.65 ? Haptic.confirm() : Haptic.reject()
                }
            } catch {
                problem = error.localizedDescription
                phase = attempt == nil ? .answering : .later
            }
        }
    }

    func reveal() {
        guard let a = attempt else { return }
        Task {
            do {
                attempt = try await API.post("/api/attempts/\(a.id)/reveal")
                phase = .reference
            } catch { problem = error.localizedDescription }
        }
    }

    func reviseAgain(_ answer: [String: Any]) {
        guard let a = attempt else { return }
        phase = .regrading
        problem = nil
        Task {
            do {
                let _: Attempt = try await API.post("/api/attempts/\(a.id)/revise", ["answer": answer])
                var r = try await API.wait(for: a.id) { $0.grade2 != nil || $0.waitsForTomorrow }
                if r.key == nil { r = try await API.post("/api/attempts/\(a.id)/reveal") }
                attempt = r
                phase = .reference
                if r.grade2 == nil { problem = "Claude reads the revision tomorrow: today's grading is used up." }
            } catch {
                problem = error.localizedDescription
                phase = .revising
            }
        }
    }

    func dispute() {
        guard let a = attempt else { return }
        Task {
            let _: JSONValue? = try? await API.post("/api/attempts/\(a.id)/dispute", ["note": "disputed from the result screen"])
            disputed = true
        }
    }
}

/// Everything under an open answer once it's sent: waiting, the verdict, the choice to revise, and
/// at the end the reference, the next step and the dispute.
struct OpenFlowPanel<Reference: View>: View {
    @Environment(AppModel.self) private var model
    let flow: OpenFlow
    let ctx: PlayContext
    var reviseTitle = "Send the Revision"
    let onRevise: () -> Void
    @ViewBuilder let reference: (Attempt) -> Reference

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = flow.problem { Text(p).foregroundStyle(Color.bad) }
            switch flow.phase {
            case .answering:
                EmptyView()
            case .grading:
                Waiting(text: "Claude is reading it against the hidden key…")
            case .verdict:
                if let a = flow.attempt {
                    VerdictCard(attempt: a)
                    RatingDelta(attempt: a)
                    HStack {
                        Button("Revise Once") { flow.phase = .revising; onRevise() }.buttonStyle(.glassProminent)
                        Button("Keep It, Show the Reference") { flow.reveal() }.buttonStyle(.glass)
                    }
                }
            case .revising:
                Text("Change your answer above, then send it. The rating moves only on the first try.")
                    .font(.callout).foregroundStyle(.secondary)
            case .regrading:
                Waiting(text: "Claude is reading the revision…")
            case .later:
                Card {
                    Text("Grading later").font(.title3.weight(.semibold))
                    Text("Claude couldn't grade this right now. It will, and the score lands in your history.").foregroundStyle(.secondary)
                }
                Button("Show the Reference") { flow.reveal() }.buttonStyle(.glass)
            case .reference:
                if let a = flow.attempt {
                    if a.grade2 != nil { VerdictCard(attempt: a, second: true) }
                    reference(a)
                    EndButtons(ctx: ctx, flow: flow)
                }
            }
        }
    }
}

/// After a game: on to the next (today, or another round) and "I think this grade is wrong".
struct EndButtons: View {
    @Environment(AppModel.self) private var model
    let ctx: PlayContext
    var flow: OpenFlow? = nil
    var attempt: Attempt? = nil
    @State private var disputed = false

    var body: some View {
        HStack {
            Button(ctx.nextTitle) { Task { await model.finished(ctx.screen) } }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            Spacer()
            if (flow?.disputed ?? false) || disputed {
                Text("Noted. It goes to your golden set.").font(.callout).foregroundStyle(.secondary)
            } else if flow != nil || attempt != nil {
                Button("I Think This Grade Is Wrong") {
                    if let flow { flow.dispute() } else if let a = attempt {
                        Task {
                            let _: JSONValue? = try? await API.post("/api/attempts/\(a.id)/dispute", ["note": "disputed from the result screen"])
                            disputed = true
                        }
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(.top, 4)
    }
}

/// The answer side of a game with a reading pane: the system inspector, always shown.
extension View {
    func answerInspector<Panel: View>(@ViewBuilder _ panel: @escaping () -> Panel) -> some View {
        inspector(isPresented: .constant(true)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { panel() }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
            .interactiveDismissDisabled()
        }
    }
}

/// The reading pane of a game: the passage, centred at a reading measure.
struct ReadingPane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 40).padding(.vertical, 28)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A plain column, for games without a separate answer side.
struct GameColumn<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.horizontal, 36).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A question asked of the player, in the interface face.
struct Ask: View {
    let text: String
    var body: some View { Text(text).font(.headline).fixedSize(horizontal: false, vertical: true) }
}
