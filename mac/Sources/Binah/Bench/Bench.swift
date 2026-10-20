import Combine
import SwiftUI

// The monthly benchmark: one sitting on a sealed form, about thirty-five minutes. No feedback until
// the end; every answer is saved as it's given, so a sitting can stop and pick up later; the results
// live on their own track, apart from practice ratings (docs/API.md, The monthly benchmark).

private let sectionNames = ["argument": "Arguments", "discern": "Fair or trick", "inference": "Reading",
                            "essay": "The essay", "talk": "The talk", "vocab": "Words"]
private let letters = Array("ABCDE")

private func pct(_ r: JSONValue?) -> String {
    guard let r, let of = r["of"]?.double, of > 0 else { return "—" }
    return "\(Int(((r["right"]?.double ?? 0) / of * 100).rounded()))%"
}
private func essayAvg(_ g: JSONValue?) -> String? {
    guard let g, g["failed"]?.bool != true, let s = g["structure"]?.double else { return nil }
    return String(format: "%.1f", (s + (g["accuracy"]?.double ?? 0) + (g["understanding"]?.double ?? 0)) / 3)
}
private func talkAvg(_ g: JSONValue?) -> String? {
    guard let g, g["failed"]?.bool != true, let d = g["deviation"]?.double else { return nil }
    return String(format: "%.1f", ((g["hesitation"]?.double ?? 0) + (g["repetition"]?.double ?? 0) + d + (g["structure"]?.double ?? 0)) / 4)
}

// MARK: the overview

struct BenchOverview: View {
    @Environment(AppModel.self) private var model
    @State private var status: BenchStatus?
    @State private var problem: String?
    @State private var selection: BenchRun.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Once a month, a sealed test you never practise on: eight arguments, eight fair-or-trick calls, two passages with three questions each, a 15-minute essay, a 2-minute talk and six words. About 35 minutes. Answers save as you go, so you can stop and come back. You see what you missed at the end.")
                    .foregroundStyle(.secondary)
                if let problem { Text(problem).foregroundStyle(Color.bad) }
                if let s = status { startCard(s); sittings(s) }
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Benchmark")
        .navigationSubtitle("A sealed test, once a month")
        .task {
            do { status = try await API.get("/api/benchmark") } catch { problem = error.localizedDescription }
        }
    }

    @ViewBuilder private func startCard(_ s: BenchStatus) -> some View {
        let open = s.runs.first { $0.finished == nil }
        let done = s.runs.filter { $0.finished != nil }
        let used = Set(s.runs.map(\.form))
        let unused = s.forms.filter { !used.contains($0.id) }.count
        let due = done.last.flatMap { Dates.stamp($0.finished) }.map { $0.addingTimeInterval(28 * 86400) }
        let early = due.map { $0 > Date() } ?? false
        Card {
            if open != nil {
                Text("You have a sitting in progress.").fontWeight(.semibold)
                Button("Continue It") { model.path = [.benchRun] }.buttonStyle(.glassProminent)
            } else if unused > 0 {
                if let due, !done.isEmpty {
                    Text(early ? "Next one is due around **\(due.formatted(.dateTime.day().month(.wide)))**. A month between sittings keeps the comparison fair." : "**A sitting is due.**")
                } else {
                    Text("**Take the first one to set your baseline.**")
                }
                Text("\(unused) sealed form\(unused == 1 ? "" : "s") ready.").font(.callout).foregroundStyle(.secondary)
                if early {
                    Button("Start One Anyway") { model.path = [.benchRun] }.buttonStyle(.glass)
                } else {
                    Button("Start a Sitting") { model.path = [.benchRun] }.buttonStyle(.glassProminent)
                }
            } else {
                Text(s.forms.isEmpty ? "No sealed forms yet." : "Every sealed form has been used.")
                Text("New ones are written on the server with python -m binah.benchgen.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func sittings(_ s: BenchStatus) -> some View {
        let done = s.runs.filter { $0.finished != nil }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Sittings")
                Table(done, selection: $selection) {
                    TableColumn("Date") { r in Text(Dates.stamp(r.finished)?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "") }
                    TableColumn("Arg.") { r in Text(pct(r.results?["argument"])).monospacedDigit() }.width(50)
                    TableColumn("Read") { r in Text(pct(r.results?["inference"])).monospacedDigit() }.width(50)
                    TableColumn("Words") { r in Text(pct(r.results?["vocab"])).monospacedDigit() }.width(50)
                    TableColumn("d′") { r in Text(r.results?["discern"]?["dprime"]?.double.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit() }.width(45)
                    TableColumn("Brier") { r in Text(r.results?["brier"]?.double.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit() }.width(50)
                    TableColumn("Essay") { r in Text(essayAvg(r.results?["essay"]?["grade"]) ?? "…").monospacedDigit() }.width(50)
                    TableColumn("Talk") { r in Text(talkAvg(r.results?["talk"]?["grade"]) ?? "…").monospacedDigit() }.width(45)
                }
                .frame(height: CGFloat(done.count) * 26 + 32)
                .clipShape(.rect(cornerRadius: 10))
                .contextMenu(forSelectionType: BenchRun.ID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { model.path = [.benchReview(id)] }
                }
                .onChange(of: selection) { if let id = selection { model.path = [.benchReview(id)] } }
                Text("Essay and talk are out of 4. Brier: 0 is perfect calibration, 0.25 a coin flip. With eight items a section, one sitting is noisy; trust a change only once it holds for two sittings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: a sitting

struct BenchStep {
    let sec: String
    let key: String
    let item: BenchItem?
    let section: BenchSection
    let passage: BenchPassage?
    let passageIndex: Int?
}

struct BenchSitting: View {
    @Environment(AppModel.self) private var model
    @State private var run: Int?
    @State private var steps: [BenchStep] = []
    @State private var answers: [String: JSONValue] = [:]
    @State private var passages: [BenchPassage] = []
    @State private var problem: String?

    var body: some View {
        Group {
            if let run {
                if let i = current {
                    stepView(steps[i], i, run).id(steps[i].key)
                } else {
                    finishScreen(run)
                }
            } else if let problem {
                ContentUnavailableView("Couldn't start a sitting", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(current.map { sectionNames[steps[$0].sec] ?? "Benchmark" } ?? "That's everything")
        .navigationSubtitle("Monthly benchmark")
        .toolbar {
            if let i = current {
                ToolbarItem(placement: .status) { Text("\(i + 1) of \(steps.count)").monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .task {
            do {
                let r: BenchStart = try await API.post("/api/benchmark/start")
                answers = r.answers ?? [:]
                passages = r.form.sections.first { $0.kind == "inference" }?.passages ?? []
                steps = Self.steps(r.form)
                run = r.run
            } catch { problem = error.localizedDescription }
        }
    }

    static func steps(_ form: BenchForm) -> [BenchStep] {
        var out: [BenchStep] = []
        for s in form.sections {
            switch s.kind {
            case "argument", "vocab", "discern":
                for it in s.items ?? [] { out.append(BenchStep(sec: s.kind, key: "\(s.kind):\(it.id)", item: it, section: s, passage: nil, passageIndex: nil)) }
            case "inference":
                for (pi, p) in (s.passages ?? []).enumerated() {
                    for q in p.questions { out.append(BenchStep(sec: "inference", key: "inference:\(q.id)", item: q, section: s, passage: p, passageIndex: pi)) }
                }
            default:
                out.append(BenchStep(sec: s.kind, key: s.kind, item: nil, section: s, passage: nil, passageIndex: nil))
            }
        }
        return out
    }

    private func answered(_ st: BenchStep) -> Bool {
        switch st.sec {
        case "essay": return answers["essay"]?["done"]?.bool == true
        case "talk": return answers["talk"] != nil && answers["talk"]?.isNull == false
        default: return answers[st.key] != nil && answers[st.key]?.isNull == false
        }
    }

    private var current: Int? { steps.firstIndex { !answered($0) } }

    private func save(_ run: Int, _ key: String, _ value: [String: Any]) async throws {
        let _: JSONValue = try await API.post("/api/benchmark/\(run)/answer", ["key": key, "value": value])
        if let data = try? JSONSerialization.data(withJSONObject: value), let v = try? JSONDecoder().decode(JSONValue.self, from: data) {
            answers[key] = v
        }
    }

    @ViewBuilder private func stepView(_ st: BenchStep, _ i: Int, _ run: Int) -> some View {
        switch st.sec {
        case "essay": BenchEssay(section: st.section, passage: passages.count > 1 ? passages[1] : passages.first,
                                 draft: answers["essay"], save: { v in try await save(run, "essay", v) })
        case "talk": BenchTalk(section: st.section, run: run, done: { answers["talk"] = .object(["audio": .bool(true)]) },
                               skip: { try await save(run, "talk", ["skipped": true]) })
        default: BenchChoice(step: st, last: i + 1 == steps.count, save: { v in try await save(run, st.key, v) })
        }
    }

    private func finishScreen(_ run: Int) -> some View {
        GameColumn {
            Text("Hand it in to see your scores and what you missed. The essay and the talk are graded on the server and arrive a minute or two later.")
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            Button("Hand It In") {
                Task {
                    do {
                        let _: JSONValue = try await API.post("/api/benchmark/\(run)/finish")
                        Haptic.confirm()
                        model.path = [.benchReview(run)]
                        await model.refreshNav()
                    } catch { problem = error.localizedDescription }
                }
            }
            .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }
}

/// A multiple-choice question (argument, reading, words) or a fair-or-trick call, with a confidence.
struct BenchChoice: View {
    let step: BenchStep
    let last: Bool
    let save: ([String: Any]) async throws -> Void
    @State private var pick: String?
    @State private var confidence = 70.0
    @State private var busy = false
    @State private var problem: String?

    private var binary: Bool { step.sec == "discern" }
    private var floor: Double { binary ? 50 : step.sec == "argument" ? 20 : 25 }

    var body: some View {
        let it = step.item
        GameColumn {
            switch step.sec {
            case "argument":
                Passage(text: it?.stimulus ?? "", size: 17)
                Ask(text: it?.stem ?? "")
            case "vocab":
                vocabSentence(it).font(.reading(19)).fixedSize(horizontal: false, vertical: true)
                Ask(text: "What does “\(it?.word ?? "")” mean here?")
            case "inference":
                DisclosureGroup("Passage \((step.passageIndex ?? 0) + 1)" + (step.passage?.source.map { " · \($0)" } ?? "")) {
                    Passage(text: step.passage?.text ?? "", size: 16).padding(.top, 6)
                }
                Ask(text: it?.stem ?? "")
            default:
                Text(it?.context ?? "").font(.callout).foregroundStyle(.secondary)
                Text(it?.text ?? "").font(.reading(20)).fixedSize(horizontal: false, vertical: true)
                Ask(text: "Manipulative as written, or a fair move?")
            }
            if binary {
                HStack {
                    option("technique", "Manipulation", nil)
                    option("fair", "Fair move", nil)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array((it?.options ?? []).enumerated()), id: \.offset) { k, o in option(String(k), o, letters[k]) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("How sure are you?"); Spacer(); Text("\(Int(confidence))%").fontWeight(.semibold).monospacedDigit() }
                Slider(value: $confidence, in: floor...100, step: 5)
            }
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            Button(last ? "Done" : "Next", action: next)
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(pick == nil || busy)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { confidence = max(floor, 70) }
        .onKeyPress(phases: .down) { press in
            let c = press.characters.uppercased()
            if binary {
                if c == "1" { pick = "technique"; return .handled }
                if c == "2" { pick = "fair"; return .handled }
            } else if let n = Int(c), n >= 1, n <= (it?.options?.count ?? 0) { pick = String(n - 1); return .handled }
            else if let l = c.first, let k = letters.firstIndex(of: l), k < (it?.options?.count ?? 0) { pick = String(k); return .handled }
            return .ignored
        }
    }

    private func option(_ value: String, _ title: String, _ letter: Character?) -> some View {
        Button {
            pick = value
            Haptic.tick()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let letter { Text(String(letter)).fontWeight(.bold).foregroundStyle(pick == value ? Color.binah : .secondary) }
                Text(title).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: binary ? .center : .leading)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(pick == value ? .binah : nil)
        .background(pick == value ? Color.binah.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
    }

    private func vocabSentence(_ it: BenchItem?) -> Text {
        let s = it?.sentence ?? "", w = it?.word ?? ""
        guard !w.isEmpty, let r = s.range(of: w, options: .caseInsensitive) else { return Text(s) }
        var a = AttributedString(s)
        if let ar = a.range(of: String(s[r])) { a[ar].backgroundColor = Color.amber.opacity(0.28) }
        return Text(a)
    }

    private func next() {
        guard let pick else { return }
        busy = true
        Task {
            do {
                try await save(binary ? ["kind": pick, "confidence": Int(confidence)] : ["choice": Int(pick) ?? 0, "confidence": Int(confidence)])
            } catch { problem = error.localizedDescription }
            busy = false
        }
    }
}

/// The fifteen-minute essay: saved as you type (every fifteen seconds and when you leave the box),
/// closed when you're done or the time is up.
struct BenchEssay: View {
    let section: BenchSection
    let passage: BenchPassage?
    let draft: JSONValue?
    let save: ([String: Any]) async throws -> Void
    @State private var text = ""
    @State private var started = Date()
    @State private var now = Date()
    @State private var lastSaved = ""
    @State private var closed = false
    @State private var problem: String?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let total = TimeInterval((section.minutes ?? 15) * 60)
        let left = max(0, total - now.timeIntervalSince(started))
        GameColumn {
            Ask(text: section.prompt ?? "")
            if let passage {
                DisclosureGroup("The passage" + (passage.source.map { " · \($0)" } ?? "")) { Passage(text: passage.text, size: 16).padding(.top, 6) }
            }
            HStack {
                Text("\(wordCount(text)) words").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(left) / 60):" + String(format: "%02d", Int(left) % 60)).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(left < 60 ? Color.bad : .primary)
            }
            AnswerBox(label: "Your essay", text: $text, minHeight: 320, readOnly: closed)
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            Button("I'm Done") { close(nil) }.buttonStyle(.glassProminent).controlSize(.large).disabled(closed)
            Text("It saves as you type. Fifteen minutes is the limit, and the reasoning counts more than the length.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .onAppear {
            text = draft?["text"]?.string ?? ""
            lastSaved = text
            if let ms = draft?["started"]?.double { started = Date(timeIntervalSince1970: ms / 1000) } else { persist(false) }
        }
        .onReceive(tick) { t in
            now = t
            guard !closed else { return }
            if t.timeIntervalSince(started) >= total { close("Time's up. Your essay is saved.") }
            else if text != lastSaved && Int(t.timeIntervalSince(started)) % 15 == 0 { persist(false) }
        }
        .onDisappear { if !closed && text != lastSaved { persist(false) } }
    }

    private func persist(_ done: Bool) {
        lastSaved = text
        let body: [String: Any] = ["text": text, "started": Int(started.timeIntervalSince1970 * 1000), "done": done]
        Task { try? await save(body) }
    }

    private func close(_ why: String?) {
        guard !closed else { return }
        closed = true
        problem = why
        lastSaved = text
        Task {
            do { try await save(["text": text, "started": Int(started.timeIntervalSince1970 * 1000), "done": true]) }
            catch { closed = false; problem = error.localizedDescription }
        }
    }
}

/// The two-minute talk, spoken; or skipped this time.
struct BenchTalk: View {
    let section: BenchSection
    let run: Int
    let done: () -> Void
    let skip: () async throws -> Void
    @State private var recorder: Recorder
    @State private var status = "Press to start, or the space bar. It stops by itself at two minutes."
    @State private var uploading = false

    init(section: BenchSection, run: Int, done: @escaping () -> Void, skip: @escaping () async throws -> Void) {
        self.section = section
        self.run = run
        self.done = done
        self.skip = skip
        _recorder = State(initialValue: Recorder(limit: TimeInterval(section.seconds ?? 120)))
    }

    var body: some View {
        GameColumn {
            Text("Two minutes, spoken. Make one point and support it.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Text(section.prompt ?? "").font(.reading(26, .semibold)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                Ring(fraction: recorder.left / recorder.limit, lineWidth: 12) {
                    Text("\(Int((recorder.state == .recording ? recorder.left : recorder.limit).rounded(.up)))")
                        .font(.system(size: 48, weight: .medium)).monospacedDigit()
                }
                .frame(width: 190, height: 190)
                Levels(levels: recorder.levels, active: recorder.state == .recording)
                Button(action: toggle) {
                    Image(systemName: recorder.state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold)).frame(width: 84, height: 84)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .tint(recorder.state == .recording ? .red : .binah)
                .disabled(uploading)
                .keyboardShortcut(.space, modifiers: [])
                Text(status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if recorder.state != .recording && !uploading {
                    Button("Skip the Talk This Time") { Task { try? await skip() } }.buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onDisappear { if recorder.state == .recording { recorder.cancel() } }
    }

    private func toggle() {
        if recorder.state == .recording { recorder.stop(); return }
        Task {
            guard await Recorder.allowed() else {
                status = "Binah can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone, or skip the talk."
                return
            }
            recorder.onFinish = { data, _ in
                uploading = true
                status = "Uploading…"
                Task {
                    do {
                        let _: JSONValue = try await API.upload("/api/benchmark/\(run)/talk", fields: [:], file: data, name: "talk.m4a", mime: "audio/mp4")
                        done()
                    } catch {
                        status = error.localizedDescription
                        recorder.state = .idle
                    }
                    uploading = false
                }
            }
            do {
                try recorder.start()
                status = "Press to stop early."
                Haptic.confirm()
            } catch { status = error.localizedDescription }
        }
    }
}

// MARK: the review

/// A finished sitting: the scores, the essay and the talk as their grades arrive, then every miss
/// with its explanation.
struct BenchReviewView: View {
    @Environment(AppModel.self) private var model
    let run: Int
    @State private var review: BenchReview?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let problem { Text(problem).foregroundStyle(Color.bad) }
                if let r = review { content(r) }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Your Sitting")
        .navigationSubtitle("Monthly benchmark" + (Dates.stamp(review?.finished).map { " · " + $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""))
        .task {
            // the essay and the talk are graded after the hand-in: ask again until both are in
            for n in 0..<80 {
                do { review = try await API.get("/api/benchmark/\(run)") } catch { problem = error.localizedDescription; return }
                guard let r = review, pending(r) else { return }
                try? await Task.sleep(nanoseconds: n < 10 ? 4_000_000_000 : 8_000_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    private func wroteEssay(_ r: BenchReview) -> Bool { !(r.answers?["essay"]?["text"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private func talked(_ r: BenchReview) -> Bool { r.answers?["talk"] != nil && r.answers?["talk"]?["skipped"]?.bool != true }
    private func pending(_ r: BenchReview) -> Bool {
        (wroteEssay(r) && (r.results?["essay"]?["grade"]).map { $0.isNull } ?? wroteEssay(r))
            || (talked(r) && (r.results?["talk"]?["grade"]).map { $0.isNull } ?? talked(r))
    }

    @ViewBuilder private func content(_ r: BenchReview) -> some View {
        let x = r.results ?? .null, dd = x["discern"] ?? .null
        let eg = x["essay"]?["grade"], tg = x["talk"]?["grade"]
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                stat(pct(x["argument"]), "arguments" + rightOf(x["argument"]))
                stat(pct(x["inference"]), "reading" + rightOf(x["inference"]))
                stat(pct(x["vocab"]), "words" + rightOf(x["vocab"]))
            }
            GridRow {
                stat(dd["dprime"]?.double.map { String(format: "%.2f", $0) } ?? "—", "discernment d′")
                stat(x["brier"]?.double.map { String(format: "%.2f", $0) } ?? "—", "calibration (Brier)")
                stat(essayAvg(eg) ?? (wroteEssay(r) ? "…" : "—"), "essay, out of 4")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        if let ot = dd["of_tricks"]?.int, ot > 0 {
            let bias = dd["bias"]?.double ?? 0
            Text("Fair or trick: caught \(dd["hits"]?.int ?? 0) of \(ot) tricks, called \(dd["false_alarms"]?.int ?? 0) of \(dd["of_fair"]?.int ?? 0) fair moves tricks. Bias \(bias > 0.15 ? "toward calling things fair" : bias < -0.15 ? "toward calling things tricks" : "balanced") (\(String(format: "%.2f", bias))).")
                .font(.callout).foregroundStyle(.secondary)
        }
        Card(title: "The essay") {
            if !wroteEssay(r) { Text("Not written this time.").foregroundStyle(.secondary) }
            else if let g = eg, !g.isNull {
                if g["failed"]?.bool == true { Text("Grading failed twice. It is logged on the server.").foregroundStyle(.secondary) }
                else {
                    Text("structure \(fmt(g["structure"]))/4 · accuracy \(fmt(g["accuracy"]))/4 · understanding \(fmt(g["understanding"]))/4"
                         + ((g["spread"]?.double ?? 0) >= 2 ? " · the two readings disagreed, so take this one loosely" : "")).font(.callout)
                    feedback(g)
                }
            } else { Waiting(text: "Being graded, twice, and averaged…") }
            if wroteEssay(r) {
                DisclosureGroup("What you wrote") {
                    Text(r.answers?["essay"]?["text"]?.string ?? "").font(.reading(15)).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }
        }
        Card(title: "The talk") {
            if !talked(r) { Text("Skipped this time.").foregroundStyle(.secondary) }
            else if let g = tg, !g.isNull {
                if g["failed"]?.bool == true { Text("Grading failed twice. It is logged on the server.").foregroundStyle(.secondary) }
                else {
                    let m = g["metrics"] ?? .null
                    Text("\(Int(m["speaking_time"]?.double ?? 0))s speaking · \(Int(m["wpm"]?.double ?? 0)) words a minute · \(String(format: "%.1f", m["fillers_per_min"]?.double ?? 0)) fillers a minute").font(.callout)
                    Text("hesitation \(fmt(g["hesitation"]))/4 · repetition \(fmt(g["repetition"]))/4 · deviation \(fmt(g["deviation"]))/4 · structure \(fmt(g["structure"]))/4").font(.callout)
                    feedback(g)
                    if let t = g["text"]?.string, !t.isEmpty {
                        DisclosureGroup("What you said") {
                            Text(t).font(.reading(15)).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        }
                    }
                }
            } else { Waiting(text: "Transcribing, then grading…") }
        }
        let misses = self.misses(r)
        SectionTitle(text: misses.isEmpty ? "What you missed" : "What you missed (\(misses.count))")
        if misses.isEmpty {
            Text("Nothing. Every multiple-choice answer was right.").foregroundStyle(.secondary)
        }
        ForEach(Array(misses.enumerated()), id: \.offset) { _, m in miss(m) }
        Button("All Sittings") { model.go(.bench) }.buttonStyle(.glass)
    }

    private func fmt(_ v: JSONValue?) -> String {
        guard let d = v?.double else { return "—" }
        return d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    private func rightOf(_ r: JSONValue?) -> String {
        guard let r, let of = r["of"]?.int else { return "" }
        return " · \(r["right"]?.int ?? 0)/\(of)"
    }

    @ViewBuilder private func feedback(_ g: JSONValue) -> some View {
        if let s = g["strength"]?.string, !s.isEmpty {
            Label { Text(s) } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.good) }
        }
        if let w = g["work_on"]?.string, !w.isEmpty {
            Label { Text(w) } icon: { Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.binah) }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Miss { let sec: String; let item: BenchItem; let mine: JSONValue }

    private func misses(_ r: BenchReview) -> [Miss] {
        var out: [Miss] = []
        let a = r.answers ?? [:]
        for s in r.form.sections {
            switch s.kind {
            case "argument", "vocab":
                for it in s.items ?? [] {
                    let m = a["\(s.kind):\(it.id)"] ?? .null
                    if m["choice"]?.int != it.answer { out.append(Miss(sec: s.kind, item: it, mine: m)) }
                }
            case "inference":
                for p in s.passages ?? [] {
                    for q in p.questions {
                        let m = a["inference:\(q.id)"] ?? .null
                        if m["choice"]?.int != q.answer { out.append(Miss(sec: "inference", item: q, mine: m)) }
                    }
                }
            case "discern":
                for it in s.items ?? [] {
                    let m = a["discern:\(it.id)"] ?? .null
                    if m["kind"]?.string != it.kind { out.append(Miss(sec: "discern", item: it, mine: m)) }
                }
            default: break
            }
        }
        return out
    }

    private func miss(_ m: Miss) -> some View {
        let it = m.item
        let conf = m.mine["confidence"]?.int.map { " (\($0)% sure)" } ?? ""
        return Card(title: sectionNames[m.sec] ?? m.sec) {
            if m.sec == "discern" {
                Text(it.text ?? "").font(.reading(16))
                let said = m.mine["kind"]?.string
                Text("You said **\(said == "technique" ? "manipulation" : said == "fair" ? "fair" : "nothing")**\(conf). It's **\(it.kind == "fair" ? "a fair move" : (it.technique ?? ""))**\(it.kind == "fair" ? ", resembling \(it.technique ?? "")" : "").")
                    .font(.callout)
                if let t = it.tell, !t.isEmpty { Text("The tell: “\(t)”").font(.callout).foregroundStyle(.secondary) }
                if let w = it.why { Text(w).font(.callout).foregroundStyle(.secondary) }
            } else {
                if m.sec == "vocab" { Text(it.sentence ?? "") }
                if m.sec == "argument" {
                    DisclosureGroup("The argument") { Passage(text: it.stimulus ?? "", size: 15).padding(.top, 6) }
                }
                Text(m.sec == "vocab" ? "“\(it.word ?? "")”" : (it.stem ?? "")).fontWeight(.semibold)
                Text("You: " + option(it, m.mine["choice"]?.int) + conf).font(.callout).foregroundStyle(Color.bad)
                Text("Answer: " + option(it, it.answer)).font(.callout).foregroundStyle(Color.good)
                if let e = it.explanation { Text(e).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private func option(_ it: BenchItem, _ k: Int?) -> String {
        guard let k, let o = it.options, k < o.count, k >= 0 else { return "no answer" }
        return "\(letters[k]). \(o[k])"
    }
}
