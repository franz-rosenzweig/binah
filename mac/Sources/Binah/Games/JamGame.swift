import SwiftUI

/// Just a Minute: sixty seconds on a topic without hesitation, repetition or deviation. The server
/// transcribes the recording and counts pauses, fillers and repeats; Claude judges deviation and
/// structure (docs/API.md, Just a Minute).
struct JamGame: View {
    let item: Item
    let ctx: PlayContext
    @State private var recorder = Recorder(limit: 60)
    @State private var phase = Phase.ready
    @State private var attempt: Attempt?
    @State private var problem: String?
    @State private var started = Date()

    enum Phase { case ready, recording, sending, grading, result }

    var body: some View {
        GameColumn {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR TOPIC").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Pillar.color("s"))
                Text(item.topic ?? "").font(.reading(30, .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Pillar.color("s").opacity(0.12), in: .rect(cornerRadius: 18))

            if phase == .ready || phase == .recording {
                recordingPanel
            } else if phase == .sending {
                Waiting(text: "Uploading the recording…")
            } else if phase == .grading {
                Waiting(text: "Transcribing on the server, then Claude listens for deviation…")
            } else if let a = attempt {
                JamResult(attempt: a)
                EndButtons(ctx: ctx, attempt: a)
            }
            if let problem { Text(problem).foregroundStyle(Color.bad) }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                if phase == .recording {
                    Label("Recording", systemImage: "record.circle").foregroundStyle(.red).symbolEffect(.pulse)
                } else {
                    Text(phase == .ready ? "60 s" : "Sent").foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear { if recorder.state == .recording { recorder.cancel() } }
    }

    private var recordingPanel: some View {
        VStack(spacing: 18) {
            Ring(fraction: recorder.left / recorder.limit, lineWidth: 12) {
                VStack(spacing: 0) {
                    Text(clock(recorder.state == .recording ? recorder.left : recorder.limit))
                        .font(.system(size: 52, weight: .medium)).monospacedDigit()
                    Text("of 1:00").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 210, height: 210)
            Levels(levels: recorder.levels, active: recorder.state == .recording)
            HStack(spacing: 8) {
                ForEach(["No hesitation", "No repetition", "No deviation"], id: \.self) { Chip(text: $0) }
            }
            Button(action: toggle) {
                Image(systemName: recorder.state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 84, height: 84)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(recorder.state == .recording ? .red : .binah)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(recorder.state == .recording ? "Stop and send" : "Start recording")
            Text(recorder.state == .recording ? "Stop sends it. Your voice goes only to your Binah server."
                 : "Press to start, or the space bar. It stops by itself at sixty seconds.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func toggle() {
        if recorder.state == .recording { recorder.stop(); return }
        Task {
            problem = nil
            guard await Recorder.allowed() else {
                problem = "Binah can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone."
                return
            }
            recorder.onFinish = { data, took in upload(data, took) }
            do {
                try recorder.start()
                started = Date()
                phase = .recording
                Haptic.confirm()
            } catch { problem = error.localizedDescription }
        }
    }

    private func upload(_ data: Data, _ took: TimeInterval) {
        phase = .sending
        Task {
            do {
                let a0: Attempt = try await API.upload("/api/audio", fields: [
                    "item_id": item.id, "day": ctx.day ?? "", "slot": String(ctx.slot ?? -1), "ms": String(Int(took * 1000)),
                ], file: data, name: "answer.m4a", mime: "audio/mp4")
                phase = .grading
                let a = a0.grading ? try await API.wait(for: a0.id) { !$0.grading || $0.waitsForTomorrow } : a0
                attempt = a
                phase = .result
                (a.score ?? 0) >= 0.65 ? Haptic.confirm() : Haptic.reject()
            } catch {
                problem = error.localizedDescription
                phase = .ready
                recorder.state = .idle
            }
        }
    }
}

/// The microphone's level, as a row of bars.
struct Levels: View {
    let levels: [Float]
    let active: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, l in
                Capsule()
                    .fill(active ? Color.binah : Color.secondary.opacity(0.35))
                    .frame(width: 4, height: max(4, CGFloat(l) * 36))
            }
        }
        .frame(height: 40)
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}

/// What the server measured and Claude judged.
struct JamResult: View {
    let attempt: Attempt
    var body: some View {
        let m = attempt.instant?["metrics"] ?? attempt.answer?["metrics"] ?? .null
        let g = attempt.grade ?? .null, ins = attempt.instant ?? .null
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    stat(num(m["speaking_time"]) + "s", "speaking")
                    stat(num(m["wpm"]), "words a minute")
                    stat(num(m["fillers_per_min"], 1), "fillers a minute")
                }
                GridRow {
                    stat(num(m["long_pauses"]), "long pauses")
                    stat("\(m["repeats"]?.array.count ?? 0)", "repeated words")
                    stat(m["first_sentence_clean"]?.bool == true ? "clean" : "not yet", "first sentence")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(attempt.later || (attempt.grade == nil && attempt.waitsForTomorrow) ? "Grading later" : band(attempt.score))
                        .font(.title2.weight(.semibold)).foregroundStyle(bandColor(attempt.score))
                    Spacer()
                }
                HStack(spacing: 6) {
                    Chip(text: "hesitation \(ins["hesitation"]?.int.map(String.init) ?? "—")/4")
                    Chip(text: "repetition \(ins["repetition"]?.int.map(String.init) ?? "—")/4")
                    Chip(text: "deviation \(g["deviation"]?.int.map(String.init) ?? "—")/4")
                    Chip(text: "structure \(g["structure"]?.int.map(String.init) ?? "—")/4")
                }
                if let s = g["strength"]?.string, !s.isEmpty {
                    Label { Text(s) } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.good) }
                }
                if let w = g["work_on"]?.string, !w.isEmpty {
                    Label { Text(w) } icon: { Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.binah) }
                }
                let devs = g["deviations"]?.strings ?? []
                if !devs.isEmpty {
                    Text("Wandered at: " + devs.map { "“\($0)”" }.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
                let reps = m["repeats"]?.array ?? []
                if !reps.isEmpty {
                    Text("Said more than twice: " + reps.map { "\($0["word"]?.string ?? "") ×\($0["count"]?.int ?? 0)" }.joined(separator: ", "))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))

            RatingDelta(attempt: attempt)
            if let t = attempt.answer?["text"]?.string, !t.isEmpty {
                DisclosureGroup("What you said") {
                    Text(t).font(.reading(15)).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func num(_ v: JSONValue?, _ digits: Int = 0) -> String {
        guard let d = v?.double else { return "—" }
        return String(format: "%.\(digits)f", d)
    }
}
