import Foundation

public struct DoctorCheck: Sendable, Codable {
    public let name: String
    public let status: Status
    public let message: String
    public let fix: String?

    public enum Status: String, Sendable, Codable {
        case ok
        case warning
        case error
    }

    public init(name: String, status: Status, message: String, fix: String?) {
        self.name = name
        self.status = status
        self.message = message
        self.fix = fix
    }
}
