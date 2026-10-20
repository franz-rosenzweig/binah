import SwiftUI
import AppKit

/// The self-test (selftest.sh): BINAH_SELFTEST=<folder>, with BINAH_BASE (a sandbox, never the real
/// Binah) and BINAH_TOKEN (a device token there). It reads every endpoint the app reads and decodes
/// it as the app does; opens every room and game and pictures the window, light and dark; and plays
/// The Author's Word once, end to end (it writes one answer to the sandbox). Then it quits, 0 if
/// everything passed.
@MainActor
enum SelfTest {
    static var failures = 0
    static var out: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["BINAH_SELFTEST"] ?? NSTemporaryDirectory()) }

    static func run(_ delegate: AppDelegate) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        log("SELFTEST against \(Server.base.absoluteString)")
        guard await until(10, { delegate.model != nil && window != nil }), let model = delegate.model else {
            check(false, "the window opens"); return finish()
        }
        window?.setContentSize(NSSize(width: 1240, height: 820))
        window?.center()

        // every answer the app reads, decoded as the app decodes it
        await decodes("today", TodayInfo.self, "/api/today")
        await decodes("nav", Nav.self, "/api/nav")
        await decodes("widget", Widget.self, "/api/widget")
        let practice = await decodes("practice", [PracticeGame].self, "/api/practice")
        await decodes("skills", SkillsInfo.self, "/api/skills")
        let golden = await decodes("golden", GoldenInfo.self, "/api/golden")
        await decodes("benchmark", BenchStatus.self, "/api/benchmark")
        await decodes("settings", ServerSettings.self, "/api/settings")
        var picks: [String: [String]] = [:]
        for g in practice ?? [] where g.live > 0 {
            guard let p = await decodes("practice/\(g.game)", PracticePick.self, "/api/practice/\(g.game)") else { continue }
            picks[g.game] = p.items
            for id in g.game == "tech" ? p.items : Array(p.items.prefix(1)) {
                let it = await decodes("item \(id)", Item.self, "/api/item/\(API.escape(id))")
                check(it.map { usable($0) } ?? false, "\(id) has what \(Games.name(g.game)) shows")
            }
        }

        // the rooms, then each game as it opens, pictured
        await model.refresh()
        for r in Room.allCases {
            model.go(r)
            await pause(2.2)
            capture("room-\(r.rawValue)")
        }
        for (game, ids) in picks.sorted(by: { $0.key < $1.key }) {
            model.go(.practice)
            model.path = [.play(game: game, ids: ids, day: nil, slot: nil)]
            await pause(2.5)
            capture("game-\(game)")
        }
        if let id = golden?.next.first {
            model.go(.golden)
            model.path = [.golden(id)]
            await pause(2.5)
            capture("golden-play")
        }
        model.go(.today)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(1.5)
        capture("room-today-dark")
        if let ids = picks["weak"] {
            model.path = [.play(game: "weak", ids: ids, day: nil, slot: nil)]
            await pause(2.5)
            capture("game-weak-dark")
        }
        NSApp.appearance = nil
        model.path = []

        // one game end to end: The Author's Word answers at once, with the key and the rating's move
        if let id = picks["word"]?.first, let item: Item = try? await API.get("/api/item/\(API.escape(id))"),
           let choice = item.options?.first {
            do {
                let a = try await submitAnswer(item, ["choice": choice], selfRating: nil, started: Date().addingTimeInterval(-5),
                                               ctx: PlayContext(game: "word", day: nil, slot: nil, screen: .play(game: "word", ids: [id], day: nil, slot: nil)))
                check(a.status == "done" && a.key?["target"]?.string != nil && a.score != nil,
                      "The Author's Word answers at once, with the key and a score", "score \(a.score ?? -1), target \(a.key?["target"]?.string ?? "-")")
                let again: Attempt = try await API.get("/api/attempts/\(a.id)")
                check(again.id == a.id, "the answer reads back")
            } catch { check(false, "The Author's Word answers", error.localizedDescription) }
        }
        finish()
    }

    /// Whether an item has the fields its game shows (docs/API.md, Items).
    static func usable(_ it: Item) -> Bool {
        switch it.game {
        case "gist": return it.passage != nil && it.inference_q != nil
        case "subtext": return it.passage != nil && it.question != nil
        case "bloat": return it.padded != nil && it.par != nil
        case "weak": return !(it.sentences ?? []).isEmpty && !(it.flaws ?? []).isEmpty
        case "word": return it.sentence?.contains("_____") == true && !(it.options ?? []).isEmpty
        case "tech": return it.text != nil && !(it.techniques ?? []).isEmpty
        case "jam": return it.topic != nil
        default: return false
        }
    }

    @discardableResult
    static func decodes<T: Decodable & Sendable>(_ what: String, _ type: T.Type, _ path: String) async -> T? {
        do {
            let v: T = try await API.get(path)
            check(true, "\(what) decodes")
            return v
        } catch {
            check(false, "\(what) decodes", error.localizedDescription)
            return nil
        }
    }

    static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.frame.width > 600 && !($0 is NSPanel) }
    }

    /// The window as it is on screen, glass and all (screencapture, run from the shell that started
    /// the test, so it needs no permission of its own).
    static func capture(_ name: String) {
        guard let w = window else { log("INFO  no window to picture for \(name)"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(w.windowNumber), out.appendingPathComponent(name + ".png").path]
        do { try p.run(); p.waitUntilExit() } catch { log("INFO  couldn't picture \(name): \(error.localizedDescription)") }
    }

    static func log(_ s: String) {
        print(s)
        if let h = try? FileHandle(forWritingTo: out.appendingPathComponent("log.txt")) {
            h.seekToEndOfFile(); h.write(Data((s + "\n").utf8)); try? h.close()
        } else {
            try? Data((s + "\n").utf8).write(to: out.appendingPathComponent("log.txt"))
        }
    }

    static func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        log((ok ? "PASS  " : "FAIL  ") + what + (detail.isEmpty ? "" : "  [\(detail.prefix(300))]"))
        if !ok { failures += 1 }
    }

    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func until(_ timeout: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; await pause(0.2) }
        return cond()
    }

    static func finish() {
        log(failures == 0 ? "SELFTEST passed" : "SELFTEST \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
