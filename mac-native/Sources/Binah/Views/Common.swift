import SwiftUI
import AppKit

// The pieces every room and game share: the pillars' colours and symbols, rings, the verdict, the
// reference, the self-rating, waiting rows and the reading face.

extension Color {
    /// A colour for light and dark appearance.
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { look in
            let v = look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                           blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }
    /// Binah's teal (style.css --accent).
    static let binah = adaptive(0x12617F, 0x85C1DC)
    static let good = adaptive(0x1F7A3F, 0xA6D189)
    static let bad = adaptive(0xB4486A, 0xEA999C)
    static let amber = adaptive(0xA2621A, 0xE5C890)
}

enum Pillar {
    static func color(_ p: String) -> Color {
        switch p {
        case "u": return .adaptive(0x2F7FB0, 0x5FA8D3)
        case "r": return .adaptive(0xB5650D, 0xD9893A)
        case "e": return .adaptive(0xB4486A, 0xD36B8C)
        default: return .adaptive(0x6E52A8, 0x9C82D4)
        }
    }
    static func symbol(_ p: String) -> String {
        switch p {
        case "u": return "book"
        case "r": return "arrow.triangle.branch"
        case "e": return "pencil.line"
        default: return "waveform"
        }
    }
    static func name(_ p: String) -> String { Games.pillarNames[p] ?? "" }
}

/// A pillar's symbol on its colour, in a rounded square, as the Mac's own settings rows draw theirs.
struct PillarIcon: View {
    let pillar: String
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: Pillar.symbol(pillar))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Pillar.color(pillar).gradient, in: .rect(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

/// A progress ring, with whatever goes in its middle.
struct Ring<Label: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 7
    var tint: Color = .binah
    @ViewBuilder var label: Label
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
    }
}

extension Font {
    /// The reading face: New York, the system's serif.
    static func reading(_ size: CGFloat = 18, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// A passage in the reading face, its paragraphs apart.
struct Passage: View {
    let text: String
    var size: CGFloat = 18
    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p).font(.reading(size)).lineSpacing(size * 0.32).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    var paragraphs: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .split(separator: "", omittingEmptySubsequences: true).map { $0.joined(separator: " ") }
    }
}

/// "From <book> · <author> · you highlighted this".
struct SourceLine: View {
    let source: ItemSource?
    var body: some View {
        if let book = source?.book, !book.isEmpty {
            HStack(spacing: 6) {
                Text("From").foregroundStyle(.secondary)
                Text(book).fontWeight(.semibold)
                if let a = source?.author, !a.isEmpty {
                    Text("· " + (a.components(separatedBy: "&").first ?? a).trimmingCharacters(in: .whitespaces)).foregroundStyle(.secondary)
                }
                if source?.highlighted == true {
                    Label("You highlighted this", systemImage: "highlighter")
                        .font(.caption).foregroundStyle(Color.amber)
                }
            }
            .font(.callout)
            .lineLimit(1)
        }
    }
}

/// What a 0–1 score is called (play.js bandOf).
func band(_ s: Double?) -> String {
    guard let s else { return "Graded" }
    return s >= 0.85 ? "Strong" : s >= 0.65 ? "Solid" : s >= 0.4 ? "Partial" : "Missed"
}

func bandColor(_ s: Double?) -> Color {
    guard let s else { return .secondary }
    return s >= 0.65 ? .good : s >= 0.4 ? .amber : .bad
}

/// A little capsule for a criterion's score.
struct Chip: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: .capsule)
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
    }
}

/// Claude's verdict on an open answer: the band, the criteria, one strength and one thing to work on,
/// and before the revision a hint (docs/API.md, Answering).
struct VerdictCard: View {
    let attempt: Attempt
    var second = false
    var body: some View {
        let g = second ? attempt.grade2 : attempt.grade
        let score = second ? attempt.score2 : attempt.score
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(band(score) + (second ? " · revised" : ""))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(bandColor(score))
                Spacer()
                if let s = attempt.self_rating, !second {
                    Text("You said \(s)/4").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let g {
                // every number on the grade is a criterion, bar `covered` (docs/API.md)
                let crit = CriteriaOrder.sorted(g.object.compactMap { k, v in
                    if case .number = v, k != "covered" { return k }
                    return nil
                })
                if !crit.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(crit, id: \.self) { k in Chip(text: "\(CriteriaOrder.label(k)) \(g[k]?.int ?? 0)/4") }
                    }
                }
                if let s = g["strength"]?.string, !s.isEmpty {
                    Label { Text(s) } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.good) }
                }
                if let w = g["work_on"]?.string, !w.isEmpty {
                    Label { Text(w) } icon: { Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.binah) }
                }
                if !second, let h = g["hint"]?.string, !h.isEmpty {
                    Label { Text("Hint: " + h).foregroundStyle(.secondary) } icon: { Image(systemName: "lightbulb") }
                        .font(.callout)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}

/// The rating's move on the first try: "Gist 1180 → 1196 +16".
struct RatingDelta: View {
    let attempt: Attempt
    var body: some View {
        if let b = attempt.rating_before, let a = attempt.rating_after {
            let d = a - b
            HStack {
                Text(Games.skillNames[attempt.skill ?? ""] ?? attempt.skill ?? "")
                Text("\(b) → \(a)").fontWeight(.semibold).monospacedDigit()
                Spacer()
                Text((d >= 0 ? "+" : "") + "\(d)")
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(d >= 0 ? Color.good : Color.bad)
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
        }
    }
}

/// A 0–4 self-rating, asked before the verdict.
struct SelfRating: View {
    @Binding var value: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How sure are you? Rate it before the verdict.").font(.callout).foregroundStyle(.secondary)
            Picker("Self-rating", selection: Binding(get: { value ?? -1 }, set: { value = $0 < 0 ? nil : $0 })) {
                ForEach(0..<5) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: 300)
        }
    }
}

struct Waiting: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

/// A labelled card for the reference and other blocks under the answer.
struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}

/// A section title over a group, as in the system's own windows.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.headline).padding(.horizontal, 4)
    }
}

/// The word count of some text, as the server counts it.
func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace }).count
}

/// Haptics on a Force Touch trackpad: a right answer, a miss, a choice.
enum Haptic {
    static func confirm() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    static func reject() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
}

/// A multi-line answer box with the system's look.
struct AnswerBox: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 90
    var readOnly = false
    var font: Font = .body
    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .disabled(readOnly)
            .accessibilityLabel(label)
    }
}
