import Foundation

/// A minimal dynamic JSON value, used to decode tool-call `args` and tool-result `result`
/// payloads whose shape varies by tool (the client only displays them).
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = if container.decodeNil() {
            .null
        } else if let value = try? container.decode(Bool.self) {
            .bool(value)
        } else if let value = try? container.decode(Double.self) {
            .number(value)
        } else if let value = try? container.decode(String.self) {
            .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            .object(value)
        } else {
            .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue? {
        if case let .object(dict) = self { return dict[key] }
        return nil
    }

    /// A scalar rendered as text, if this value is a string/number/bool.
    public var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            // `Int(_:)` traps on a whole value outside Int range (e.g. a ns timestamp in tool
            // args); `Int(exactly:)` returns nil there so we fall back to the Double form.
            if value == value.rounded(), let int = Int(exactly: value) { return String(int) }
            return String(value)
        case let .bool(value):
            return String(value)
        default:
            return nil
        }
    }

    public var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}
