import Foundation

// The API's answers (binah/app.py), as the native app reads them. Fields the app doesn't need are
// left out; anything that may be missing is optional, so a new field on the server never breaks it.

// MARK: today

struct TodayInfo: Decodable {
    let edition: Edition
    let week: Week
    let counts: Counts
    let ratings: [String: Rating]
    let skills: [String: SkillMeta]
    let games: [String: GameMeta]
}

struct Edition: Decodable {
    let day: String
    let slots: [Slot]
    let recall: Recall?
    let finished: Bool

    var done: Int { slots.filter(\.done).count }
    var next: Slot? { slots.first { !$0.done } }
    var minutesLeft: Int { slots.filter { !$0.done }.reduce(0) { $0 + $1.minutes } }
}

struct Slot: Decodable, Identifiable, Hashable {
    let slot: Int
    let game: String
    let name: String?
    let pillar: String?
    let minutes: Int
    let items: [String]
    let done: Bool
    let answered: Int?
    let source: String?
    let scores: [Double?]?
    var id: Int { slot }

    var average: Double? {
        let s = (scores ?? []).compactMap { $0 }
        return s.isEmpty ? nil : s.reduce(0, +) / Double(s.count)
    }
}

struct Recall: Decodable {
    let item: String?
    let book: String?
    let reference: String?
    let key_points: [String]?
    let mark: String?
}

struct Week: Decodable {
    let days: [WeekDay]
    let active: Int
    let goal: Int
}

struct WeekDay: Decodable, Identifiable {
    let day: String
    let answers: Int
    let rest: Bool
    let future: Bool
    let today: Bool
    var id: String { day }
}

struct Counts: Decodable {
    let editions: Int
    let answers: Int
    let passages: Int
    let arguments: Int
    let minutes_spoken: Double
    let active_weeks: Int
}

struct Rating: Decodable {
    let rating: Int
    let n: Int
    let calibrating: Bool
}

struct SkillMeta: Decodable {
    let pillar: String
    let name: String
}

struct GameMeta: Decodable {
    let name: String
    let skill: String
    let lane: String
    let minutes: Int
    let blurb: String
    let round: Int?
}

// MARK: practice, skills, nav, settings

struct PracticeGame: Decodable, Identifiable {
    let game: String
    let name: String
    let minutes: Int
    let blurb: String
    let live: Int
    var id: String { game }
}

struct PracticePick: Decodable { let items: [String] }

struct SkillsInfo: Decodable {
    let ratings: [String: Rating]
    let skills: [String: SkillMeta]
    let recent: [String: [Double]]
    let discern: Discern
    let self_gap: Double?
    let bench_due: Bool
}

struct Discern: Decodable {
    let n: Int
    let dprime: Double?
    let bias: Double?
    let hit_rate: Double?
    let false_alarms: Double?
    let brier: Double?
}

struct Nav: Decodable {
    struct DoneOf: Decodable { let done: Int; let total: Int }
    struct Golden: Decodable { let n: Int; let target: Int }
    struct ActiveOf: Decodable { let active: Int; let goal: Int }
    let today: DoneOf
    let golden: Golden
    let bench_due: Bool
    let week: ActiveOf
    let rest_weekday: Int?
}

struct ServerSettings: Codable, Equatable {
    var weekly_goal_days: Int?
    var rest_weekday: Int?
    var grading_tone: String?
}

struct Widget: Codable, Equatable {
    struct Next: Codable, Equatable { let game: String; let name: String }
    struct Wk: Codable, Equatable { let active: Int; let goal: Int }
    let day: String
    let done: Int
    let total: Int
    let finished: Bool
    let minutes_left: Double?
    let next: Next?
    let week: Wk?
}

struct Saved: Decodable { let ok: Bool?; let message: String? }
struct Device: Decodable { let name: String; let token: String }

// MARK: items and attempts

struct ItemSource: Decodable {
    let book: String?
    let author: String?
    let highlighted: Bool?
}

/// One playable item, as /api/item sends it: never the key.
struct Item: Decodable, Identifiable {
    let id: String
    let game: String
    let skill: String?
    let source: ItemSource?
    // gist, subtext
    let passage: String?
    let inference_q: String?
    let question: String?
    // weak
    let sentences: [String]?
    let flaws: [String]?
    // tech
    let text: String?
    let context: String?
    let techniques: [String]?
    // word
    let sentence: String?
    let options: [String]?
    // bloat
    let padded: String?
    let par: Int?
    // jam
    let topic: String?
}

/// One answer and what came of it: answer → verdict → one revision → the reference (app.py).
struct Attempt: Decodable, Identifiable {
    let id: Int
    let item_id: String
    let game: String
    let status: String
    let self_rating: Int?
    let answer: JSONValue?
    let instant: JSONValue?
    let grade: JSONValue?
    let revision: JSONValue?
    let grade2: JSONValue?
    let score: Double?
    let score2: Double?
    let rating_before: Int?
    let rating_after: Int?
    let skill: String?
    let disputed: String?
    let key: JSONValue?
    /// A grade (or a revision's, or a weak step's reason) waits for tomorrow: the daily cap was hit.
    let grading_later: Bool?

    var grading: Bool { status == "grading" }
    var later: Bool { status == "later" }
    /// Nothing more will come today: stop polling.
    var waitsForTomorrow: Bool { grading_later == true || later }
}

// MARK: golden set

struct GoldenInfo: Decodable {
    let report: GoldenReport
    let next: [String]
    let rubrics: [String: Rubric]
    let disputed: [Attempt]
}

struct GoldenReport: Decodable {
    let target: Int
    let total: Int
    let games: [String: GoldenGame]
}

struct GoldenGame: Decodable {
    let scored: Int
    let graded: Int
    let criteria: [String: Agreement]
}

struct Agreement: Decodable {
    let n: Int
    let exact: Double?
    let within1: Double?
    let lenient: Double?
    let qwk: Double?
}

struct Rubric: Decodable {
    let version: Int
    let criteria: [String: [String]]
    var ordered: [String] { CriteriaOrder.sorted(criteria.keys) }
}

struct GoldenKey: Decodable { let key: JSONValue }

// MARK: the benchmark

struct BenchStatus: Decodable {
    let forms: [BenchFormInfo]
    let runs: [BenchRun]
}

struct BenchFormInfo: Decodable { let id: String; let created: String?; let sections: [String] }

struct BenchRun: Decodable, Identifiable {
    let id: Int
    let form: String
    let started: String?
    let finished: String?
    let results: JSONValue?
}

struct BenchStart: Decodable {
    let run: Int
    let form: BenchForm
    let answers: [String: JSONValue]?
}

struct BenchReview: Decodable {
    let run: Int
    let form: BenchForm
    let answers: [String: JSONValue]?
    let results: JSONValue?
    let started: String?
    let finished: String?
}

struct BenchForm: Decodable {
    let id: String
    let sections: [BenchSection]
}

struct BenchSection: Decodable {
    let kind: String
    let items: [BenchItem]?
    let passages: [BenchPassage]?
    let prompt: String?
    let minutes: Int?
    let seconds: Int?
}

struct BenchPassage: Decodable {
    let source: String?
    let text: String
    let questions: [BenchItem]
}

/// A question on a form. The review sends `answer` and `explanation` too, and for fair-or-trick
/// `kind`, `technique`, `tell` and `why`.
struct BenchItem: Decodable {
    let id: FlexID
    let stimulus: String?
    let stem: String?
    let options: [String]?
    let sentence: String?
    let word: String?
    let text: String?
    let context: String?
    let answer: Int?
    let explanation: String?
    let kind: String?
    let technique: String?
    let tell: String?
    let why: String?
}

// MARK: dates

enum Dates {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-10-20" at noon, so no time zone moves it to another day.
    static func day(_ s: String) -> Date? {
        isoDay.date(from: String(s.prefix(10))).map { $0.addingTimeInterval(12 * 3600) }
    }

    /// A server timestamp, with or without its zone ("2026-10-19 23:18:24", "…T23:18:25+00:00").
    static func stamp(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: " ", with: "T")
        if !(s.contains("+") || s.hasSuffix("Z")) { s += "Z" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
