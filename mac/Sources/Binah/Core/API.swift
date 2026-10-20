import Foundation
import Security

/// Where Binah is: the public address by default, a sandbox for testing (Settings → This Mac).
enum Server {
    static let baseKey = "baseURL"
    static let defaultBase = "https://binah.tiresia.xyz"

    static var base: URL {
        let s = ProcessInfo.processInfo.environment["BINAH_BASE"] ?? UserDefaults.standard.string(forKey: baseKey) ?? defaultBase
        return normal(s) ?? URL(string: defaultBase)!
    }

    /// http or https, a host, a port if any, no path.
    static func normal(_ s: String) -> URL? {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespaces)), let scheme = u.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = u.host, !host.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = u.port
        return c.url
    }

    static func setBase(_ s: String) -> Bool {
        guard let u = normal(s) else { return false }
        UserDefaults.standard.set(u.absoluteString, forKey: baseKey)
        return true
    }

    static func url(_ path: String) -> URL { URL(string: base.absoluteString + path)! }
}

/// This Mac's device token (docs/API.md, Signing in), kept in the login keychain where the web-view
/// app before it kept its own, so a token it made still signs this one in.
enum Token {
    static let deviceName = "mac"
    private static let service = "xyz.tiresia.binah"
    private static let account = "device token"
    nonisolated(unsafe) private static var cached: String??

    static var value: String? {
        if let env = ProcessInfo.processInfo.environment["BINAH_TOKEN"], !env.isEmpty { return env }
        if let cached { return cached }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let t = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
            ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cached = .some(t)
        return t
    }

    @discardableResult
    static func set(_ token: String?) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var ok = true
        if let token, !token.isEmpty {
            var add = base
            add[kSecValueData as String] = Data(token.utf8)
            add[kSecAttrLabel as String] = "Binah device token"
            ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        cached = .some(ok ? token : nil)
        return ok
    }
}

enum APIError: LocalizedError {
    case signedOut
    case refused(Int, String)
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sign in to Binah again."
        case .refused(_, let why): return why
        case .unreachable(let why): return "Binah didn't answer: \(why)"
        }
    }
    var status: Int? { if case .refused(let s, _) = self { return s }; return nil }
}

/// Binah's JSON API (docs/API.md), with this Mac's bearer token.
enum API {
    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Binah/\(v) (macOS)"
    }
    /// Told when the server says 401, so the app can ask for a sign-in.
    nonisolated(unsafe) static var onSignedOut: (@MainActor () -> Void)?

    static func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        try decode(try await send(path, method: "GET", body: nil, type: nil))
    }

    static func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], as: T.Type = T.self) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try decode(try await send(path, method: "POST", body: data, type: "application/json"))
    }

    /// A multipart POST: the fields, then the file (Just a Minute, the benchmark's talk).
    static func upload<T: Decodable>(_ path: String, fields: [String: String], file: Data, name: String, mime: String,
                                     as: T.Type = T.self) async throws -> T {
        let boundary = "binah-\(UUID().uuidString)"
        var body = Data()
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try decode(try await send(path, method: "POST", body: body, type: "multipart/form-data; boundary=\(boundary)"))
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw APIError.refused(0, "Binah's answer wasn't what this app expects (\(T.self)): \(error)")
        }
    }

    private static func send(_ path: String, method: String, body: Data?, type: String?) async throws -> Data {
        guard let token = Token.value else {
            await MainActor.run { onSignedOut?() }
            throw APIError.signedOut
        }
        var r = URLRequest(url: Server.url(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let type { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        r.httpBody = body
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: r) } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            await MainActor.run { onSignedOut?() }
            throw APIError.signedOut
        }
        guard (200..<300).contains(status) else { throw APIError.refused(status, detail(data) ?? "Binah answered \(status).") }
        return data
    }

    static func detail(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
    }

    /// Signs in with the username and password, once, and keeps a device token instead of the cookie:
    /// POST /api/login, then POST /api/devices with the cookie, on a session that forgets it after.
    static func signIn(user: String, password: String) async throws {
        let session = URLSession(configuration: .ephemeral)
        func post(_ path: String, _ body: [String: Any]) async throws -> Data {
            var r = URLRequest(url: Server.url(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: r) } catch {
                throw APIError.unreachable(error.localizedDescription)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw APIError.refused(status, detail(data) ?? "Binah answered \(status).") }
            return data
        }
        _ = try await post("/api/login", ["user": user, "password": password])
        let d = try JSONDecoder().decode(Device.self, from: try await post("/api/devices", ["name": Token.deviceName]))
        session.invalidateAndCancel()
        guard Token.set(d.token) else { throw APIError.refused(0, "The Keychain didn't take this Mac's token.") }
    }

    /// Polls an attempt every 1.5 s, then every 3 s, until `done` says so (docs/API.md, Answering).
    static func wait(for id: Int, until done: (Attempt) -> Bool) async throws -> Attempt {
        for i in 0..<200 {
            let a: Attempt = try await get("/api/attempts/\(id)")
            if done(a) { return a }
            try await Task.sleep(nanoseconds: i < 10 ? 1_500_000_000 : 3_000_000_000)
        }
        return try await get("/api/attempts/\(id)")
    }

    static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? id
    }
}
