import SwiftUI
import Charts

// MARK: Practice

/// Every game, any time: the server picks items you'd get about 75% right (docs/API.md, Practice).
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var games: [PracticeGame] = []
    @State private var problem: String?
    @AppStorage("practiceFilter") private var filter = "all"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Anything beyond today's edition. The daily edition is the one that counts for the week.")
                    .foregroundStyle(.secondary)
                if let problem { Text(problem).foregroundStyle(Color.bad) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(games.filter { filter == "all" || Games.pillar[$0.game] == filter }) { g in
                        GameCard(game: g) { Task { await model.practice(g.game) } }
                    }
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Practice")
        .navigationSubtitle("Extra rounds, any time")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Skill", selection: $filter) {
                    Text("All").tag("all")
                    ForEach(["u", "r", "e", "s"], id: \.self) { p in Text(Pillar.name(p)).tag(p) }
                }
                .pickerStyle(.segmented).fixedSize()
            }
        }
        .task {
            do { games = try await API.get("/api/practice") } catch { problem = error.localizedDescription }
        }
    }
}

struct GameCard: View {
    let game: PracticeGame
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let p = Games.pillar[game.game] ?? "u"
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    PillarIcon(pillar: p, size: 32)
                    Spacer()
                    Text("\(game.minutes) min").font(.callout).foregroundStyle(.secondary)
                }
                Text(game.name).font(.headline)
                Text(game.blurb).font(.callout).foregroundStyle(.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(Pillar.name(p)) · " + (game.live > 0 ? "\(game.live) ready" : "none yet")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hover ? Color.binah.opacity(0.5) : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(game.live == 0)
        .onHover { hover = $0 }
    }
}

// MARK: Skills

/// Ratings of the first try, unaided, with each skill's recent trend; discernment measured honestly;
/// how well you judge yourself; and the benchmark (docs/API.md, Skills).
struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var info: SkillsInfo?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Ratings measure your first try, unaided. They say “calibrating” until there's enough to go on.")
                    .foregroundStyle(.secondary)
                if let problem { Text(problem).foregroundStyle(Color.bad) }
                if let s = info {
                    VStack(spacing: 0) {
                        ForEach(Array(Games.skillOrder.enumerated()), id: \.element) { i, k in
                            if i > 0 { Divider().padding(.leading, 52) }
                            skillRow(k, s)
                        }
                    }
                    .background(.background.secondary, in: .rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Fair or trick, honestly measured")
                        Card {
                            if let d = s.discern.dprime, let bias = s.discern.bias {
                                Text("Discernment **d′ \(d, specifier: "%.2f")** · bias \(bias > 0.15 ? "toward calling things fair" : bias < -0.15 ? "toward calling things tricks" : "balanced") (\(bias, specifier: "%.2f"))")
                                Text("Caught \(Int(((s.discern.hit_rate ?? 0) * 100).rounded()))% of the tricks, flagged \(Int(((s.discern.false_alarms ?? 0) * 100).rounded()))% of the fair moves as tricks." + (s.discern.brier.map { " Confidence Brier score \($0) (0 is perfect, 0.25 is a coin flip)." } ?? ""))
                                    .font(.callout).foregroundStyle(.secondary)
                            } else {
                                Text("After a few rounds of Technique or Fair Move, this shows whether you're getting sharper or just more suspicious.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "How well you judge yourself")
                        Card {
                            if let g = s.self_gap {
                                Text("Your self-rating is off from the grade by **\(g, specifier: "%.2f")** points on average (on 0–4). Watch it shrink.")
                            } else {
                                Text("Rate yourself before each verdict, and this tracks the gap.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Away from practice")
                        Button { model.go(.bench) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "flag.fill").foregroundStyle(.white).frame(width: 30, height: 30)
                                    .background(Pillar.color("r").gradient, in: .rect(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("The monthly benchmark").fontWeight(.semibold)
                                    Text("A sealed test, about 35 minutes. The honest measure of whether practice transfers.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if s.bench_due {
                                    Text("Due").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.bad, in: .capsule)
                                }
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(14).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .background(.background.secondary, in: .rect(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Skills")
        .navigationSubtitle("Your first try, unaided")
        .task {
            do { info = try await API.get("/api/skills") } catch { problem = error.localizedDescription }
        }
    }

    private func skillRow(_ k: String, _ s: SkillsInfo) -> some View {
        let meta = s.skills[k]
        let r = s.ratings[k]
        let recent = s.recent[k] ?? []
        return HStack(spacing: 12) {
            PillarIcon(pillar: meta?.pillar ?? "u", size: 28)
            Text(meta?.name ?? Games.skillNames[k] ?? k).fontWeight(.semibold).frame(width: 110, alignment: .leading)
            HStack(spacing: 6) {
                Text(r.map { "\($0.rating)" } ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
                if r?.calibrating == true { Chip(text: "calibrating") }
            }
            .frame(width: 150, alignment: .leading)
            if recent.count >= 2 {
                Chart(Array(recent.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Answer", i), y: .value("Score", v)).foregroundStyle(Color.binah).interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 28)
            } else {
                Text("A few more answers and a trend shows here.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: Golden set

/// Score your own answers with Claude's rubric; fifty of them say whether its grades deserve your
/// trust (docs/API.md, The golden set).
struct GoldenView: View {
    @Environment(AppModel.self) private var model
    @State private var info: GoldenInfo?
    @State private var problem: String?

    struct Row: Identifiable {
        let game: String, criterion: String, a: Agreement
        var id: String { game + "/" + criterion }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Answer an item, then score your own answer with the same rubric Claude uses. Fifty of these tell you whether its grades deserve your trust.")
                    .foregroundStyle(.secondary)
                if let problem { Text(problem).foregroundStyle(Color.bad) }
                if let g = info {
                    Card {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(g.report.total) of \(g.report.target)").font(.title.weight(.semibold)).monospacedDigit()
                            Spacer()
                            Text("scored by you").foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(g.report.total), total: Double(max(1, g.report.target))).tint(Color.binah)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Score one now")
                        if g.next.isEmpty {
                            Text("No items left to score in these games.").foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(g.next.enumerated()), id: \.element) { i, id in
                                    if i > 0 { Divider().padding(.leading, 56) }
                                    let game = String(id.split(separator: ":").first ?? "")
                                    Button { model.path = [.golden(id)] } label: {
                                        HStack(spacing: 12) {
                                            PillarIcon(pillar: Games.pillar[game] ?? "u", size: 30)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(Games.name(game)).fontWeight(.semibold)
                                                Text("Answer it, then grade yourself").font(.callout).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text("2 min").font(.callout).foregroundStyle(.secondary)
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .background(.background.secondary, in: .rect(cornerRadius: 12))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "How Claude agrees with you")
                        let rows = ["gist", "subtext", "bloat"].flatMap { game -> [Row] in
                            guard let gg = g.report.games[game] else { return [] }
                            return CriteriaOrder.sorted(gg.criteria.keys).map { Row(game: Games.name(game), criterion: CriteriaOrder.label($0), a: gg.criteria[$0]!) }
                        }
                        Table(rows) {
                            TableColumn("Game", value: \.game)
                            TableColumn("Criterion", value: \.criterion)
                            TableColumn("n") { r in Text("\(r.a.n)").monospacedDigit() }.width(40)
                            TableColumn("Exact") { r in Text(r.a.n > 0 ? pct(r.a.exact) : "—").monospacedDigit() }.width(60)
                            TableColumn("±1") { r in Text(r.a.n > 0 ? pct(r.a.within1) : "—").monospacedDigit() }.width(60)
                            TableColumn("Lenient") { r in Text(r.a.n > 0 ? r.a.lenient.map { ($0 > 0 ? "+" : "") + String(format: "%.2g", $0) } ?? "—" : "—").monospacedDigit() }.width(60)
                            TableColumn("QWK") { r in Text(r.a.qwk.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit() }.width(50)
                        }
                        .frame(height: CGFloat(rows.count) * 26 + 32)
                        .clipShape(.rect(cornerRadius: 10))
                        Text("Claude grades golden answers blind (without your anchors). “Lenient” above zero means it scores higher than you do. QWK of 0.6–0.7 is typical for open judgments; above 0.8 is very good.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !g.disputed.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Grades you disputed")
                            ForEach(g.disputed) { a in
                                Card {
                                    Text("\(Games.name(a.game)) · \(a.score.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")").fontWeight(.semibold)
                                    Text(a.disputed ?? "").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 32).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Golden Set")
        .navigationSubtitle(info.map { "\($0.report.total) of \($0.report.target) scored by you" } ?? "")
        .task {
            do { info = try await API.get("/api/golden") } catch { problem = error.localizedDescription }
        }
    }

    private func pct(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

// MARK: the Settings window

/// Binah → Settings… (⌘,): your rhythm and Claude's tone (kept on the server), your account, and
/// what this Mac keeps (the address, the menu bar).
struct SettingsWindow: View {
    var body: some View {
        TabView {
            Tab("Practice", systemImage: "calendar") { RhythmSettings() }
            Tab("Account", systemImage: "person.crop.circle") { AccountSettings() }
            Tab("This Mac", systemImage: "desktopcomputer") { ThisMacSettings() }
        }
        .frame(width: 480)
        .tint(Color.binah)
    }
}

struct RhythmSettings: View {
    @Environment(AppModel.self) private var model
    @State private var s: ServerSettings?
    @State private var problem: String?

    var body: some View {
        Form {
            if let problem { Text(problem).foregroundStyle(Color.bad) }
            if !model.signedIn {
                Text("Sign in to Binah first.").foregroundStyle(.secondary)
            } else if s != nil {
                Section {
                    Picker("Days a week I aim for", selection: binding(\.weekly_goal_days, 4)) {
                        ForEach(1...7, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Rest day", selection: binding(\.rest_weekday, -1)) {
                        Text("None").tag(-1)
                        ForEach(0..<7, id: \.self) { Text(Weekdays.name($0)).tag($0) }
                    }
                } footer: { Text("The rest day counts as on track for the week.") }
                Section {
                    Picker("How Claude talks to me", selection: Binding(get: { s?.grading_tone ?? "balanced" }, set: { save(\.grading_tone, $0) })) {
                        Text("Soft").tag("soft"); Text("Balanced").tag("balanced"); Text("Strict").tag("strict")
                    }
                    .pickerStyle(.inline)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
        .task(id: model.signedIn) {
            guard model.signedIn else { return }
            do { s = try await API.get("/api/settings") } catch { problem = error.localizedDescription }
        }
    }

    private func binding(_ k: WritableKeyPath<ServerSettings, Int?>, _ none: Int) -> Binding<Int> {
        Binding(get: { s?[keyPath: k] ?? none }, set: { save(k, $0 == -1 ? nil : $0) })
    }

    private func save<V>(_ k: WritableKeyPath<ServerSettings, V>, _ v: V) {
        s?[keyPath: k] = v
        guard let cur = s else { return }
        var body: [String: Any] = [:]
        body["weekly_goal_days"] = cur.weekly_goal_days
        body["rest_weekday"] = cur.rest_weekday as Any? ?? NSNull()
        body["grading_tone"] = cur.grading_tone
        Task {
            do {
                s = try await API.post("/api/settings", body)
                problem = nil
                await model.refreshNav()
            } catch { problem = error.localizedDescription }
        }
    }
}

struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @State private var current = ""
    @State private var new = ""
    @State private var said: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section("Password") {
                SecureField("Current password", text: $current).textContentType(.password)
                SecureField("New password", text: $new).textContentType(.newPassword)
                HStack {
                    if let said { Text(said).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Change Password", action: change).disabled(busy || current.isEmpty || new.count < 10 || !model.signedIn)
                }
            }
            Section {
                HStack {
                    Text(model.signedIn ? "Signed in on this Mac as “\(Token.deviceName)”." : "Not signed in.")
                    Spacer()
                    Button("Sign Out") { model.signOut() }.disabled(!model.signedIn)
                }
            } footer: { Text("A new password needs 10 or more characters, and signs out every other browser.") }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }

    private func change() {
        busy = true
        Task {
            do {
                let _: JSONValue = try await API.post("/api/account", ["current": current, "password": new])
                said = "Changed. Other browsers are signed out."
                current = ""; new = ""
            } catch { said = error.localizedDescription }
            busy = false
        }
    }
}

struct ThisMacSettings: View {
    @Environment(AppModel.self) private var model
    @State private var address = Server.base.absoluteString
    @State private var note: String?
    @AppStorage(MenuBarPrefs.key) private var menuBar = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Address", text: $address, prompt: Text(Server.defaultBase)).labelsHidden()
                    Button("Use") {
                        if Server.setBase(address.isEmpty ? Server.defaultBase : address) {
                            address = Server.base.absoluteString
                            note = "Binah now opens from \(address). Sign in there once."
                            model.signOut()
                        } else { note = "That isn't an address Binah can use. It starts with https:// or http://." }
                    }
                    .disabled(Server.normal(address)?.absoluteString == Server.base.absoluteString)
                }
            } header: { Text("Binah's address") } footer: { Text(note ?? "https://binah.tiresia.xyz, or a sandbox for testing.") }
            Section {
                Toggle("Show today's edition in the menu bar", isOn: $menuBar)
            } footer: { Text("Off while the web-view Binah app shows its own; on once this one replaces it.") }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
