import Foundation

// Handling for ISO8601 Timestamps with fractional seconds
// Directly from https://stackoverflow.com/questions/46458487/

extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self {
        .init(includingFractionalSeconds: true)
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601withOptionalFractionalSeconds = custom {
        let string = try $0.singleValueContainer().decode(String.self)
        if let withFractional = try? Date(string, strategy: .iso8601withFractionalSeconds) {
            return withFractional
        }
        if let plain = try? Date(string, strategy: .iso8601) {
            return plain
        }
        // Be tolerant: a single unparseable timestamp must not throw and wedge an entire
        // response (or a live chat stream frame). Fall back to a sentinel instead.
        return .distantPast
    }
}

extension FormatStyle where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self {
        .init(includingFractionalSeconds: true)
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static let iso8601withFractionalSeconds = custom {
        var container = $1.singleValueContainer()
        try container.encode($0.formatted(.iso8601withFractionalSeconds))
    }
}

public extension Date {
    static func == (lhs: Date, rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 0.001
    }
}
