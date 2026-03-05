import Foundation

public struct JSONOutput: Sendable {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static func string<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
