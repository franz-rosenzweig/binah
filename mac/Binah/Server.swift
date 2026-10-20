import AppKit
import Security
import WebKit

/// Where Binah is. The window loads the live site (docs/SHELL.md); the base URL is a
/// setting, with the public address as the default and a sandbox as the other.
enum Server {
    static let baseKey = "baseURL"
    static let defaultBase = "https://binah.tiresia.xyz"

    static var base: URL {
        let s = UserDefaults.standard.string(forKey: baseKey) ?? defaultBase
        return URL(string: s.trimmingCharacters(in: .whitespaces)).flatMap(normal) ?? URL(string: defaultBase)!
    }

    /// An address as Binah keeps it: http or https, a host, a port if any, no path.
    static func normal(_ u: URL) -> URL? {
        guard let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host, !host.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = u.port
        return c.url
    }

    /// A page of the app ("#today") or a path on the server ("/api/save").
    static func url(_ where_: String) -> URL {
        if where_.hasPrefix("#") { return URL(string: base.absoluteString + "/" + where_)! }
        return URL(string: base.absoluteString + (where_.hasPrefix("/") ? where_ : "/" + where_))!
    }

    private static func port(_ scheme: String?, _ port: Int?) -> Int {
        if let port, port != 0 { return port }
        return scheme?.lowercased() == "https" ? 443 : 80
    }

    /// A page the window may show: the base URL's origin and nothing else.
    static func isOurs(_ u: URL) -> Bool {
        u.scheme?.lowercased() == base.scheme && u.host?.lowercased() == base.host?.lowercased()
            && port(u.scheme, u.port) == port(base.scheme, base.port)
    }

    /// The same, for the origin that asks for the microphone.
    static func isOurs(_ o: WKSecurityOrigin) -> Bool {
        o.protocol.lowercased() == base.scheme && o.host.lowercased() == base.host?.lowercased()
            && port(o.protocol, o.port) == port(base.scheme, base.port)
    }

    static func setBase(_ s: String) -> Bool {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespaces)).flatMap(normal) else { return false }
        guard u != base else { return true }
        UserDefaults.standard.set(u.absoluteString, forKey: baseKey)
        NotificationCenter.default.post(name: .binahBaseChanged, object: nil)
        return true
    }
}

extension Notification.Name {
    /// The base URL changed: windows load again, the menu bar asks again.
    static let binahBaseChanged = Notification.Name("binah.baseChanged")
    /// The device token changed: the menu bar asks again.
    static let binahTokenChanged = Notification.Name("binah.tokenChanged")
}

/// The device token the menu bar and Train on This use (`Authorization: Bearer`,
/// docs/SHELL.md §5), never the window's cookie. Kept in the login keychain. The
/// self-test starts from its own (-SelfTestToken) and keeps any new one in memory; it
/// never touches the keychain.
@MainActor
enum Token {
    private static let service = "xyz.tiresia.binah"
    private static let account = "device token"
    private static var cached: String??

    private static var testing: Bool { UserDefaults.standard.string(forKey: "SelfTestOut") != nil }

    static var value: String? {
        if testing {
            if cached == nil {
                // selftest.sh passes "t:<token>": a bare token can start with "-"
                let t = UserDefaults.standard.string(forKey: "SelfTestToken").map { $0.hasPrefix("t:") ? String($0.dropFirst(2)) : $0 }
                cached = .some(t.flatMap { $0.isEmpty ? nil : $0 })
            }
            return cached ?? nil
        }
        if let cached { return cached }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let found = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
        let t = found ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cached = .some(t)
        return t
    }

    /// Saves a new token, or forgets it with nil or "". False if the keychain said no.
    @discardableResult
    static func set(_ token: String?) -> Bool {
        let t = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if testing {
            cached = .some(t.isEmpty ? nil : t)
            NotificationCenter.default.post(name: .binahTokenChanged, object: nil)
            return true
        }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var ok = true
        if !t.isEmpty {
            var add = base
            add[kSecValueData as String] = Data(t.utf8)
            add[kSecAttrLabel as String] = "Binah device token"
            ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        cached = .some(t.isEmpty || !ok ? nil : t)
        NotificationCenter.default.post(name: .binahTokenChanged, object: nil)
        return ok
    }
}

/// The two endpoints the native parts use with the token (docs/SHELL.md §6, §7).
enum Client {
    /// GET /api/widget: today's edition at a glance.
    struct Widget: Codable, Equatable {
        struct Next: Codable, Equatable { var game: String; var name: String }
        struct Week: Codable, Equatable { var active: Int; var goal: Int }
        var day: String
        var done: Int
        var total: Int
        var finished: Bool
        var minutes_left: Double?
        var next: Next?
        var week: Week?
    }

    enum Failure: LocalizedError {
        case noToken, refused(String), unreachable(String)
        var errorDescription: String? {
            switch self {
            case .noToken: return "This Mac isn't connected yet. Connect it in Settings."
            case .refused(let why): return why
            case .unreachable(let why): return "Binah didn't answer: \(why)"
            }
        }
    }

    static func widget() async throws -> Widget {
        let data = try await request("/api/widget")
        return try JSONDecoder().decode(Widget.self, from: data)
    }

    /// POST /api/save: a link or a passage to train on. Answers the server's message.
    static func save(url: String?, text: String?, title: String?) async throws -> String {
        var body: [String: String] = [:]
        if let url, !url.isEmpty { body["url"] = url }
        if let text, !text.isEmpty { body["text"] = text }
        if let title, !title.isEmpty { body["title"] = title }
        let data = try await request("/api/save", json: body)
        let said = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
        return said ?? "Saved."
    }

    private static func request(_ path: String, json: [String: String]? = nil) async throws -> Data {
        guard let token = await Token.value else { throw Failure.noToken }
        var r = URLRequest(url: Server.url(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(await UserAgent.shell, forHTTPHeaderField: "User-Agent")
        if let json {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: r) } catch {
            throw Failure.unreachable(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw Failure.refused(code == 401 ? "Binah doesn't know this Mac's token any more. Connect it again in Settings."
                                  : detail ?? "Binah answered \(code)")
        }
        return data
    }
}

@MainActor
enum UserAgent {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    /// What the page looks for (docs/SHELL.md §1).
    static var name: String { "Binah/\(version) (macOS shell)" }
    static var shell: String { "Binah/\(version) (macOS shell) CFNetwork" }
}
