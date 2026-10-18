import Foundation

/// Decimal decoding preserves the provider's decimal representation without a Double intermediate.
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Decimal.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { object[key] ?? .null }
    public var object: [String: JSONValue] { if case .object(let v) = self { v } else { [:] } }
    public var array: [JSONValue] { if case .array(let v) = self { v } else { [] } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var decimal: Decimal? { if case .number(let v) = self { v } else { nil } }
    public var int: Int? { decimal.map { NSDecimalNumber(decimal: $0).intValue } }
    public var bool: Bool { if case .bool(let v) = self { v } else { false } }
    public var textID: String? { string ?? decimal.map(\.exact) }
    public var decimals: [String: Decimal] { object.compactMapValues(\.decimal) }
}

extension Decimal {
    public var exact: String { NSDecimalNumber(decimal: self).stringValue }
    public static func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil,
              let result = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !result.isNaN,
              normalizedDecimal(value) == normalizedDecimal(result.exact) else { return nil }
        return result
    }

    /// Decimal(string:) can silently discard digits beyond its capacity. Reject such
    /// input rather than storing a rounded scoring multiplier.
    private static func normalizedDecimal(_ input: String) -> String {
        let negative = input.hasPrefix("-")
        let unsigned = input.hasPrefix("-") || input.hasPrefix("+") ? String(input.dropFirst()) : input
        let pieces = unsigned.split(separator:".",omittingEmptySubsequences:false)
        let whole = String((pieces.first ?? "").drop(while: { $0 == "0" }))
        var fraction = pieces.count > 1 ? String(pieces[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        let zero = whole.isEmpty && fraction.isEmpty
        return (negative && !zero ? "-" : "") + (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
    }
}
