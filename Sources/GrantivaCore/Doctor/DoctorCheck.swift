import Foundation

public struct DoctorCheck: Sendable, Codable {
    public let name: String
    public let status: Status
    public let message: String
    public let fix: String?
    public let section: Section

    public enum Status: String, Sendable, Codable {
        case ok
        case warning
        case error
    }

    public enum Section: String, Sendable, Codable {
        case required = "Required"
        case project = "Project"
        case cloud = "CI / Cloud"
    }

    public init(name: String, status: Status, message: String, fix: String?, section: Section = .required) {
        self.name = name
        self.status = status
        self.message = message
        self.fix = fix
        self.section = section
    }
}
