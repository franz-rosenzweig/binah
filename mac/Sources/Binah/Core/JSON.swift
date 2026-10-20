import Foundation

/// A JSON value of any shape, for the parts of an answer the server keeps free-form: the answer
/// itself, code's instant scoring, Claude's grade and the key (games.py). Read with the accessors.
enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var int: Int? { double.map { Int($0.rounded()) } }
    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return nil
        }
    }
    var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSONValue] { if case .object(let o) = self { return o }; return [:] }
    var strings: [String] { array.compactMap(\.string) }
    var isNull: Bool { if case .null = self { return true }; return false }

    /// A plain Foundation value, for a request body.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }
}

/// An id the server sends as a string or a number (benchmark items), kept as a string.
struct FlexID: Decodable, Hashable, Sendable, CustomStringConvertible {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = String(try c.decode(Double.self)) }
    }
    var description: String { value }
}

/// The order criteria are listed in (games.py RUBRICS), since a JSON object's order doesn't survive
/// decoding; anything new comes after, alphabetically.
enum CriteriaOrder {
    static let known = ["main_idea", "accuracy", "concision", "inference", "precision", "meaning",
                        "hesitation", "repetition", "deviation", "structure", "understanding", "reason"]
    static func sorted(_ keys: some Collection<String>) -> [String] {
        keys.sorted { a, b in
            let ia = known.firstIndex(of: a) ?? Int.max, ib = known.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
    }
    /// "main_idea" → "main idea".
    static func label(_ key: String) -> String { key.replacingOccurrences(of: "_", with: " ") }
}
