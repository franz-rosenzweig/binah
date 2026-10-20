import SwiftUI

/// The window: sign-in until there's a token, then the sidebar and the room in front, with games
/// and the benchmark pushed on top of their room.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.signedIn {
                SignInView()
            } else {
                NavigationSplitView {
                    Sidebar()
                } detail: {
                    NavigationStack(path: $model.path) {
                        RoomView()
                            .navigationDestination(for: Screen.self) { ScreenView(screen: $0) }
                    }
                }
            }
        }
        .tint(Color.binah)
        .sheet(isPresented: $model.showTrain) { TrainOnThisSheet().tint(Color.binah) }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.room }, set: { if let r = $0 { model.go(r) } })) {
            Section("Train") {
                ForEach(Room.train) { r in row(r) }
            }
            Section("Measure") {
                ForEach(Room.measure) { r in row(r) }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 228)
        .safeAreaInset(edge: .bottom) { WeekCard().padding(10) }
    }

    @ViewBuilder private func row(_ r: Room) -> some View {
        let n = model.nav
        HStack {
            Label(r.title, systemImage: r.symbol)
            Spacer()
            switch r {
            case .today:
                if let t = n?.today, t.total > 0 { Text("\(t.done) of \(t.total)").foregroundStyle(.secondary).monospacedDigit() }
            case .golden:
                if let g = n?.golden { Text("\(g.n) of \(g.target)").foregroundStyle(.secondary).monospacedDigit() }
            case .bench:
                if n?.bench_due == true {
                    Text("Due").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 1).background(Color.bad, in: .capsule)
                }
            default: EmptyView()
            }
        }
        .font(.callout)
        .tag(r)
    }
}

/// The week at the foot of the sidebar: days active against the goal.
struct WeekCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let n = model.nav {
            HStack(spacing: 10) {
                Ring(fraction: n.week.goal > 0 ? Double(n.week.active) / Double(n.week.goal) : 0, lineWidth: 4) { EmptyView() }
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(n.week.active) of \(n.week.goal) days this week").font(.callout.weight(.semibold))
                    Text(n.rest_weekday.map { "\(Weekdays.name($0)) is your rest day" } ?? "No rest day set")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
}

enum Weekdays {
    static let all = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static func name(_ i: Int) -> String { (0..<7).contains(i) ? all[i] : "" }
}

struct RoomView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.room ?? .today {
        case .today: TodayView()
        case .practice: PracticeView()
        case .skills: SkillsView()
        case .golden: GoldenView()
        case .bench: BenchOverview()
        }
    }
}

struct ScreenView: View {
    let screen: Screen
    var body: some View {
        switch screen {
        case .play(let game, let ids, let day, let slot):
            GameView(game: game, ids: ids, day: day, slot: slot, screen: screen)
        case .golden(let id): GoldenPlay(itemID: id)
        case .benchRun: BenchSitting()
        case .benchReview(let run): BenchReviewView(run: run)
        }
    }
}

/// Sign in once with the username and password; Binah then knows this Mac by a device token.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var user = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("binah").font(.system(size: 44, weight: .medium, design: .serif)).italic()
                    Text("בינה").font(.system(size: 32, weight: .bold, design: .serif)).foregroundStyle(Color.binah)
                }
                Text("Understanding, trained on real text.").foregroundStyle(.secondary)
            }
            Form {
                TextField("Username", text: $user).textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password).onSubmit(go)
            }
            .formStyle(.grouped)
            .frame(width: 360)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            if let problem { Text(problem).foregroundStyle(Color.bad).frame(width: 340) }
            Button(action: go) {
                Text(busy ? "Signing In…" : "Sign In").frame(width: 200)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(busy || user.isEmpty || password.isEmpty)
            .keyboardShortcut(.defaultAction)
            Text("Binah at \(Server.base.host ?? Server.base.absoluteString). Another address: Binah → Settings → This Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func go() {
        guard !busy else { return }
        busy = true
        problem = nil
        Task {
            do {
                try await API.signIn(user: user, password: password)
                password = ""
                model.signedIn(true)
            } catch { problem = error.localizedDescription }
            busy = false
        }
    }
}
