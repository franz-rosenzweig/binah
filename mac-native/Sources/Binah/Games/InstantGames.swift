import SwiftUI

// The games code scores at once: Find the Weak Step, The Author's Word and Technique or Fair Move?
// The answer comes back done, with the score, the rating's move and the key (docs/API.md).

// MARK: Find the Weak Step

/// An argument, a sentence at a time: pick where the reasoning is weakest (or call it sound), name
/// the flaw, and optionally say why in one line, which Claude reads afterwards.
struct WeakGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var pick: Int?
    @State private var flaw: String?
    @State private var why = ""
    @State private var attempt: Attempt?
    @State private var sending = false
    @State private var problem: String?
    @State private var started = Date()

    private let sound = "none (sound)"

    var body: some View {
        ReadingPane {
            SourceLine(source: item.source)
            Text("Pick the sentence where the reasoning is weakest, or call it sound.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((item.sentences ?? []).enumerated()), id: \.offset) { i, s in
                    if s == "¶" { Spacer().frame(height: 10) } else { sentence(i, s) }
                }
            }
        }
        .answerInspector {
            Ask(text: "What's wrong with it?")
            Picker("Flaw", selection: Binding(get: { flaw ?? "" }, set: { flaw = $0; Haptic.tick() })) {
                ForEach(item.flaws ?? [], id: \.self) { f in Text(f.prefix(1).uppercased() + f.dropFirst()).tag(f) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(attempt != nil)
            Ask(text: "Why, in one line?")
            TextField("Optional; Claude reads it", text: $why, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .disabled(attempt != nil)
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            if attempt == nil {
                Button(sending ? "Checking…" : "Check Answer", action: send)
                    .buttonStyle(.glassProminent)
                    .disabled(sending || flaw == nil || (pick == nil && flaw != sound))
                    .keyboardShortcut(.defaultAction)
            } else if let a = attempt {
                result(a)
            }
        }
    }

    private func sentence(_ i: Int, _ s: String) -> some View {
        let ins = attempt?.instant
        let isKey = ins?["key_index"]?.int == i
        let isMiss = attempt != nil && pick == i && ins?["spot_ok"]?.bool == false
        let picked = pick == i
        let tint: Color = isKey ? .good : isMiss ? .bad : .binah
        return Button {
            guard attempt == nil else { return }
            pick = i
            Haptic.tick()
        } label: {
            Text(s)
                .font(.reading(18))
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background((picked || isKey || isMiss) ? tint.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((picked || isKey || isMiss) ? tint.opacity(0.45) : .clear))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder private func result(_ a: Attempt) -> some View {
        let k = a.key ?? .null, ins = a.instant ?? .null
        let score = a.score ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(score >= 1 ? "Clean" : score > 0 ? "Half right" : "Missed")
                    .font(.title2.weight(.semibold)).foregroundStyle(score >= 1 ? Color.good : score > 0 ? Color.amber : Color.bad)
                Spacer()
                Text("spot \(ins["spot_ok"]?.bool == true ? "✓" : "✗") · flaw \(ins["flaw_ok"]?.bool == true ? "✓" : "✗")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("**\((k["flaw"]?.string ?? "").capitalizedFirst).** \(k["explain"]?.string ?? "")")
            if let s = k["assumption"]?.string, !s.isEmpty { Text("**It quietly assumes:** \(s)") }
            if !why.trimmingCharacters(in: .whitespaces).isEmpty {
                if let g = a.grade, let w = g["work_on"]?.string {
                    Text("**Your reason:** \(g["reason"]?.int.map { "\($0)/4" } ?? "?"). \(w)").font(.callout)
                } else if a.waitsForTomorrow {
                    Text("Claude reads your reason tomorrow: today's grading is used up.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Waiting(text: "Claude is reading your reason…")
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        RatingDelta(attempt: a)
        EndButtons(ctx: ctx, attempt: a)
    }

    private func send() {
        sending = true
        problem = nil
        Task {
            do {
                var a = try await submitAnswer(item, ["index": pick as Any? ?? NSNull(), "flaw": flaw ?? "", "why": why.trimmingCharacters(in: .whitespacesAndNewlines)],
                                               selfRating: nil, started: started, ctx: ctx)
                attempt = a
                (a.score ?? 0) >= 1 ? Haptic.confirm() : Haptic.reject()
                if !why.trimmingCharacters(in: .whitespaces).isEmpty && a.grade == nil && !a.waitsForTomorrow {
                    a = try await API.wait(for: a.id) { $0.grade != nil || $0.waitsForTomorrow }
                    attempt = a
                }
            } catch { problem = error.localizedDescription }
            sending = false
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: The Author's Word

/// A sentence with one word gone; pick the one the author actually chose.
struct WordGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var chosen: String?
    @State private var attempt: Attempt?
    @State private var problem: String?
    @State private var started = Date()

    var body: some View {
        ReadingPane {
            SourceLine(source: item.source)
            sentenceText.font(.reading(22)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
        }
        .answerInspector {
            Ask(text: "Which word did the author choose?")
            VStack(spacing: 8) {
                ForEach(item.options ?? [], id: \.self) { w in
                    Button { choose(w) } label: {
                        HStack {
                            Text(w).font(.reading(17))
                            Spacer()
                            if let m = mark(w) { Image(systemName: m.0).foregroundStyle(m.1) }
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(chosen != nil)
                }
            }
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            if let a = attempt {
                let k = a.key ?? .null
                VStack(alignment: .leading, spacing: 8) {
                    Text((a.score ?? 0) > 0 ? "The author's word" : "The author wrote “\(k["target"]?.string ?? "")”")
                        .font(.title3.weight(.semibold)).foregroundStyle((a.score ?? 0) > 0 ? Color.good : Color.bad)
                    Text(k["why"]?.string ?? "")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 14))
                RatingDelta(attempt: a)
                EndButtons(ctx: ctx, attempt: a)
            }
        }
    }

    /// The sentence with its gap drawn as a rule, or filled once the key is in.
    private var sentenceText: Text {
        let parts = (item.sentence ?? "").components(separatedBy: "_____")
        let fill = attempt?.key?["target"]?.string
        var a = AttributedString(parts.first ?? "")
        for p in parts.dropFirst() {
            if let fill {
                var f = AttributedString(fill)
                f.foregroundColor = Color.binah
                f.font = .reading(22, .semibold)
                a += f
            } else {
                var gap = AttributedString("            ")
                gap.underlineStyle = .single
                a += gap
            }
            a += AttributedString(p)
        }
        return Text(a)
    }

    private func mark(_ w: String) -> (String, Color)? {
        guard let a = attempt else { return nil }
        let target = a.key?["target"]?.string?.lowercased()
        if w.lowercased() == target { return ("checkmark.circle.fill", .good) }
        if w == chosen { return ("xmark.circle.fill", .bad) }
        return nil
    }

    private func choose(_ w: String) {
        chosen = w
        Task {
            do {
                let a = try await submitAnswer(item, ["choice": w], selfRating: nil, started: started, ctx: ctx)
                attempt = a
                (a.score ?? 0) > 0 ? Haptic.confirm() : Haptic.reject()
            } catch {
                problem = error.localizedDescription
                chosen = nil
            }
        }
    }
}

// MARK: Technique or Fair Move?

/// Six quick calls: is this manipulation, or a fair version of the same move? With a confidence, so
/// the round can say how well calibrated you are, and Skills whether you're getting sharper or just
/// more suspicious.
struct TechRound: View {
    @Environment(AppModel.self) private var model
    let ids: [String]
    let ctx: PlayContext
    @State private var index = 0
    @State private var item: Item?
    @State private var results: [Attempt] = []
    @State private var kind: String?
    @State private var technique: String?
    @State private var confidence = 70.0
    @State private var attempt: Attempt?
    @State private var problem: String?
    @State private var started = Date()
    @State private var discern: Discern?

    var body: some View {
        Group {
            if index >= ids.count {
                summary
            } else if let item {
                ReadingPane {
                    Text(item.context ?? "").font(.callout).foregroundStyle(.secondary)
                    techText(item).font(.reading(21)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                }
                .answerInspector { panel(item) }
            } else if let problem {
                ContentUnavailableView("Couldn't open it", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 4) {
                    ForEach(0..<ids.count, id: \.self) { j in
                        Capsule().fill(dotColor(j)).frame(width: 16, height: 5)
                    }
                }
                .accessibilityLabel("\(min(index + 1, ids.count)) of \(ids.count)")
            }
        }
        .task(id: index) { await load() }
    }

    private func dotColor(_ j: Int) -> Color {
        if j < results.count { return results[j].instant?["kind_ok"]?.bool == true ? .good : .bad }
        return j == index ? .binah : Color.secondary.opacity(0.3)
    }

    private func load() async {
        guard index < ids.count else {
            discern = (try? await API.get("/api/skills", as: SkillsInfo.self))?.discern
            return
        }
        item = nil
        kind = nil; technique = nil; confidence = 70; attempt = nil; problem = nil
        started = Date()
        do { item = try await API.get("/api/item/\(API.escape(ids[index]))") } catch { problem = error.localizedDescription }
    }

    /// The text, with the tell (the phrase that gives it away) marked once the call is made.
    private func techText(_ item: Item) -> Text {
        let text = item.text ?? ""
        guard let tell = attempt?.key?["tell"]?.string, !tell.isEmpty, let r = text.range(of: tell) else { return Text(text) }
        var a = AttributedString(text)
        if let ar = a.range(of: tell) {
            a[ar].backgroundColor = Color.amber.opacity(0.28)
        }
        _ = r
        return Text(a)
    }

    @ViewBuilder private func panel(_ item: Item) -> some View {
        Ask(text: "Manipulative as written, or a fair move?")
        HStack(spacing: 8) {
            callButton("technique", "Manipulation")
            callButton("fair", "Fair move")
        }
        if kind == "technique" {
            Text("Which technique? (optional, a bonus if right)").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(item.techniques ?? [], id: \.self) { t in
                    Toggle(t.capitalizedFirst, isOn: Binding(get: { technique == t }, set: { technique = $0 ? t : nil }))
                        .toggleStyle(.checkbox)
                        .disabled(attempt != nil)
                }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("How sure are you?")
                Spacer()
                Text("\(Int(confidence))%").fontWeight(.semibold).monospacedDigit()
            }
            Slider(value: $confidence, in: 50...100, step: 5).disabled(attempt != nil)
        }
        if let problem { Text(problem).foregroundStyle(Color.bad) }
        if let a = attempt {
            let k = a.key ?? .null, ins = a.instant ?? .null
            VStack(alignment: .leading, spacing: 8) {
                Text((ins["kind_ok"]?.bool == true ? "Right" : "Not quite") + " · " + (k["kind"]?.string == "fair" ? "a fair move" : (k["technique"]?.string ?? "")))
                    .font(.title3.weight(.semibold)).foregroundStyle(ins["kind_ok"]?.bool == true ? Color.good : Color.bad)
                if k["kind"]?.string == "fair", let t = k["technique"]?.string {
                    Text("It resembles \(t), done fairly.").font(.callout).foregroundStyle(.secondary)
                } else if ins["label_ok"]?.bool == true {
                    Text("And you named the technique.").font(.callout).foregroundStyle(.secondary)
                }
                Text(k["why"]?.string ?? "")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
            Button(index + 1 < ids.count ? "Next" : "See the Round") {
                results.append(a)
                index += 1
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        } else {
            Button("Call It", action: call)
                .buttonStyle(.glassProminent)
                .disabled(kind == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func callButton(_ k: String, _ title: String) -> some View {
        let key = attempt?.key?["kind"]?.string
        let tint: Color? = attempt == nil ? (kind == k ? .binah : nil) : key == k ? .good : kind == k ? .bad : nil
        return Button {
            kind = k
            if k != "technique" { technique = nil }
            Haptic.tick()
        } label: {
            Text(title).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(tint)
        .background(tint.map { $0.opacity(0.14) } ?? .clear, in: .rect(cornerRadius: 8))
        .disabled(attempt != nil)
    }

    private func call() {
        guard let item else { return }
        Task {
            do {
                let a = try await submitAnswer(item, ["kind": kind ?? "", "technique": kind == "technique" ? (technique as Any? ?? NSNull()) : NSNull(),
                                                      "confidence": Int(confidence)], selfRating: nil, started: started, ctx: ctx)
                attempt = a
                a.instant?["kind_ok"]?.bool == true ? Haptic.confirm() : Haptic.reject()
            } catch { problem = error.localizedDescription }
        }
    }

    private var summary: some View {
        let right = results.filter { $0.instant?["kind_ok"]?.bool == true }.count
        let briers = results.compactMap { $0.instant?["brier"]?.double }
        return GameColumn {
            Card {
                Text("\(right) of \(results.count) called right").font(.title2.weight(.semibold))
                if !briers.isEmpty {
                    Text("Confidence Brier score this round: **\(briers.reduce(0, +) / Double(briers.count), specifier: "%.3f")** (0 is perfect, 0.25 is a coin flip).")
                }
                if let d = discern, let dp = d.dprime, let bias = d.bias {
                    Text("Over all your rounds: discernment d′ **\(dp, specifier: "%.2f")**, \(bias > 0.15 ? "leaning toward calling things fair" : bias < -0.15 ? "leaning toward calling things tricks" : "no lean either way").")
                } else {
                    Text("After a few rounds, Skills shows whether you are getting sharper or just more suspicious.").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(ctx.fromToday ? "Back to Today" : "Another Round") { Task { await model.finished(ctx.screen) } }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
    }
}
