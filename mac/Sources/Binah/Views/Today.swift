import SwiftUI

/// Today: the edition (a few games, about six minutes), yesterday's recall card, the week and the
/// totals so far (docs/API.md, Today).
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let t = model.today {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        EditionHero(today: t)
                        if let r = t.edition.recall, r.mark == nil, r.reference != nil {
                            RecallCard(recall: r).id(t.edition.day)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Games")
                            GamesList(today: t)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) { WeekSection(week: t.week); CountsSection(counts: t.counts) }
                            VStack(alignment: .leading, spacing: 24) { WeekSection(week: t.week); CountsSection(counts: t.counts) }
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 32).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Today")
        .navigationSubtitle(model.today.flatMap { Dates.day($0.edition.day) }?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? "")
        .toolbar {
            if let t = model.today, let next = t.edition.next {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.play(next, day: t.edition.day) } label: {
                        Label("Continue Edition", systemImage: "play.fill").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .task { await model.refresh() }
    }
}

struct EditionHero: View {
    @Environment(AppModel.self) private var model
    let today: TodayInfo

    var body: some View {
        let ed = today.edition
        HStack(spacing: 20) {
            Ring(fraction: ed.slots.isEmpty ? 0 : Double(ed.done) / Double(ed.slots.count)) {
                Text("\(ed.done)/\(ed.slots.count)").font(.title3.weight(.semibold)).monospacedDigit()
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                if ed.finished || ed.next == nil {
                    Text("Today's edition is done.").font(.title2.weight(.bold))
                    Text("Tomorrow opens with a recall card on today's passage. Anything else today is extra, in Practice.")
                        .foregroundStyle(.secondary)
                } else if let next = ed.next {
                    Text("Today's edition").font(.title2.weight(.bold))
                    Text("\(ed.slots.count) games · about \(max(1, ed.minutesLeft)) minutes left").foregroundStyle(.secondary)
                    Text("Next is \(next.name ?? Games.name(next.game))" + (next.source.map { ", from \($0)" } ?? "") + ".")
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if let next = ed.next, !ed.finished {
                Button("Continue") { model.play(next, day: ed.day) }
                    .buttonStyle(.glassProminent).controlSize(.large)
            } else {
                Button("Practice") { model.go(.practice) }.buttonStyle(.glass).controlSize(.large)
            }
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

/// Yesterday's passage: what you remember, then the reference, then how much you got.
struct RecallCard: View {
    @Environment(AppModel.self) private var model
    let recall: Recall
    @State private var text = ""
    @State private var shown = false
    @State private var gone = false

    var body: some View {
        if !gone {
            Card(title: "Before you start") {
                Text("Yesterday you read a passage" + (recall.book.map { " from \($0)" } ?? "") + ". What was its point?")
                AnswerBox(label: "What you remember", text: $text, minHeight: 60, readOnly: shown)
                if !shown {
                    Button("Check Against Yesterday's Reference") { shown = true }.buttonStyle(.glass)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recall.reference ?? "").font(.reading(16)).italic()
                        ForEach(recall.key_points ?? [], id: \.self) { k in
                            Label(k, systemImage: "circle.fill").labelStyle(BulletStyle())
                        }
                    }
                    .padding(.top, 4)
                    Text("How much did you remember?").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        ForEach([("yes", "Got It"), ("partly", "Partly"), ("no", "Not Really")], id: \.0) { m, title in
                            Button(title) { mark(m) }.buttonStyle(.glass)
                        }
                    }
                }
            }
        }
    }

    private func mark(_ m: String) {
        Task {
            do {
                let _: JSONValue = try await API.post("/api/today/recall", ["answer": text, "mark": m])
                withAnimation { gone = true }
                model.flash("Noted. On to today.")
            } catch { model.flash(error.localizedDescription) }
        }
    }
}

struct BulletStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

/// The edition's games, as an inset list: the pillar, the game, where it's from, and how it went.
struct GamesList: View {
    @Environment(AppModel.self) private var model
    let today: TodayInfo

    var body: some View {
        let ed = today.edition
        VStack(spacing: 0) {
            if ed.slots.isEmpty {
                Text("No items yet. Run the passage engine or import content.").foregroundStyle(.secondary).padding(16)
            }
            ForEach(Array(ed.slots.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider().padding(.leading, 56) }
                Button { model.play(s, day: ed.day) } label: { row(s, next: s.slot == ed.next?.slot) }
                    .buttonStyle(.plain)
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func row(_ s: Slot, next: Bool) -> some View {
        let p = s.pillar ?? Games.pillar[s.game] ?? "u"
        let meta = today.games[s.game]
        return HStack(spacing: 12) {
            PillarIcon(pillar: p, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(meta?.name ?? Games.name(s.game)).fontWeight(.semibold)
                Text(Pillar.name(p) + (s.source.map { " · \($0)" } ?? "")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if s.done {
                Label(s.average.map { "\(Int(($0 * 100).rounded()))%" } ?? "Done", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Color.good)
            } else {
                if next {
                    Text("Next").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.binah, in: .capsule)
                }
                if let a = s.answered, a > 0 {
                    Text("\(a)/\(s.items.count)").font(.callout).foregroundStyle(Color.amber).monospacedDigit()
                } else {
                    Text("\(meta?.minutes ?? s.minutes) min").font(.callout).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(next ? Color.binah.opacity(0.07) : .clear)
        .contentShape(.rect)
    }
}

struct WeekSection: View {
    @Environment(AppModel.self) private var model
    let week: Week
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "This week")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(week.days) { d in
                        VStack(spacing: 6) {
                            Text(Dates.day(d.day)?.formatted(.dateTime.weekday(.narrow)) ?? "").font(.caption).foregroundStyle(.secondary)
                            dot(d)
                        }
                        .frame(maxWidth: .infinity)
                        .help(d.day)
                    }
                }
                Text("\(week.active) of \(week.goal) days this week." + (model.nav?.rest_weekday.map { " \(Weekdays.name($0)) counts as on track." } ?? ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func dot(_ d: WeekDay) -> some View {
        let size: CGFloat = 20
        if d.answers > 0 {
            Circle().fill(Color.binah).frame(width: size, height: size)
                .overlay { if d.today { Circle().stroke(Color.binah, lineWidth: 2).padding(-3) } }
        } else if d.rest {
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).foregroundStyle(.secondary).frame(width: size, height: size)
        } else if d.today {
            Circle().strokeBorder(Color.binah, lineWidth: 2).background(Circle().fill(Color.binah.opacity(0.15))).frame(width: size, height: size)
        } else {
            Circle().fill(.quaternary).frame(width: size, height: size)
        }
    }
}

struct CountsSection: View {
    let counts: Counts
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "So far")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    stat(counts.editions, "editions finished"); stat(counts.passages, "passages read"); stat(counts.arguments, "arguments weighed")
                }
                GridRow {
                    stat(counts.answers, "answers"); stat(Int(counts.minutes_spoken.rounded()), "minutes spoken"); stat(counts.active_weeks, "active weeks")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
