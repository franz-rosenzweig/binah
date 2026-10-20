import SwiftUI

/// The sidebar's rooms. Settings live in the Settings window (⌘,), as in any Mac app.
enum Room: String, CaseIterable, Identifiable, Hashable {
    case today, practice, skills, golden, bench
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .practice: return "Practice"
        case .skills: return "Skills"
        case .golden: return "Golden Set"
        case .bench: return "Benchmark"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "calendar"
        case .practice: return "square.grid.2x2"
        case .skills: return "chart.bar"
        case .golden: return "star"
        case .bench: return "flag"
        }
    }
    static let train: [Room] = [.today, .practice, .skills]
    static let measure: [Room] = [.golden, .bench]
}

/// What a room opens on top of itself: a game, a golden-set item, a benchmark sitting or its review.
enum Screen: Hashable {
    case play(game: String, ids: [String], day: String?, slot: Int?)
    case golden(String)
    case benchRun
    case benchReview(Int)
}

@MainActor @Observable
final class AppModel {
    var signedIn = Token.value != nil
    var room: Room? = .today
    var path: [Screen] = []
    var nav: Nav?
    var today: TodayInfo?
    var toast: String?
    var showTrain = false
    /// Bumped when today's edition may have moved, so Today loads again.
    var todayVersion = 0

    init() {
        API.onSignedOut = { [weak self] in self?.signOut(expired: true) }
    }

    func start() async {
        guard signedIn else { return }
        await refresh()
    }

    func refresh() async {
        async let n: Nav? = try? API.get("/api/nav")
        async let t: TodayInfo? = try? API.get("/api/today")
        let (nv, td) = await (n, t)
        if let nv { nav = nv }
        if let td { today = td }
        todayVersion += 1
    }

    func refreshNav() async {
        if let n: Nav = try? await API.get("/api/nav") { nav = n }
    }

    func go(_ r: Room) {
        room = r
        path = []
    }

    /// One of today's games, counted for today.
    func play(_ s: Slot, day: String) {
        path = [.play(game: s.game, ids: s.items, day: day, slot: s.slot)]
    }

    /// A practice round of a game: the server picks items at about 75% expected success.
    func practice(_ game: String) async {
        do {
            let p: PracticePick = try await API.get("/api/practice/\(game)")
            path = [.play(game: game, ids: p.items, day: nil, slot: nil)]
        } catch { flash(error.localizedDescription) }
    }

    /// After a game: today again (and its counts), or another round.
    func finished(_ screen: Screen) async {
        if case .play(let game, _, let day, _) = screen, day == nil {
            await practice(game)
        } else {
            path = []
            await refresh()
        }
    }

    func back() {
        if !path.isEmpty { path.removeLast() }
        Task { await refresh() }
    }

    func flash(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }

    func signedIn(_ yes: Bool) {
        signedIn = yes
        if yes { Task { await refresh() } }
    }

    func signOut(expired: Bool = false) {
        Token.set(nil)
        signedIn = false
        today = nil
        nav = nil
        path = []
        if expired { flash("Binah asked for a fresh sign-in.") }
    }

    var gamesMeta: [String: GameMeta] { today?.games ?? [:] }
}

/// The games' names and pillars, also known without a network answer.
enum Games {
    static let names = ["gist": "Gist & Infer", "subtext": "Subtext", "weak": "Find the Weak Step",
                        "tech": "Technique or Fair Move?", "word": "The Author's Word", "bloat": "Cut the Bloat",
                        "jam": "Just a Minute"]
    static let pillar = ["gist": "u", "subtext": "u", "weak": "r", "tech": "r", "word": "e", "bloat": "e", "jam": "s"]
    static let skillNames = ["gist": "Gist", "inference": "Inference", "weak": "Weak steps", "discern": "Fair or trick",
                             "precision": "Precision", "concision": "Concision", "fluency": "Fluency"]
    static let skillOrder = ["gist", "inference", "weak", "discern", "precision", "concision", "fluency"]
    static let pillarNames = ["u": "Understand", "r": "Reason", "e": "Express", "s": "Speak"]
    static func name(_ g: String) -> String { names[g] ?? g }
}
