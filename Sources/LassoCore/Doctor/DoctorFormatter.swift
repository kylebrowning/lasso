import Foundation

public struct DoctorFormatter: Sendable {
    public init() {}

    public func format(_ checks: [DoctorCheck]) -> String {
        var lines: [String] = []
        let maxNameWidth = checks.map(\.name.count).max() ?? 0

        for check in checks {
            let icon: String
            switch check.status {
            case .ok:      icon = "✓"
            case .warning: icon = "⚠"
            case .error:   icon = "✗"
            }
            let padded = check.name.padding(toLength: maxNameWidth, withPad: " ", startingAt: 0)
            lines.append("\(icon) \(padded)  \(check.message)")
            if let fix = check.fix {
                let padding = String(repeating: " ", count: maxNameWidth + 4)
                lines.append("\(padding)\(fix)")
            }
        }

        let errors = checks.filter { $0.status == .error }.count
        let warnings = checks.filter { $0.status == .warning }.count
        lines.append("")
        lines.append("\(errors) error\(errors == 1 ? "" : "s") · \(warnings) warning\(warnings == 1 ? "" : "s")")
        lines.append("")
        lines.append("Run `lasso doctor --json` for machine-readable output.")

        return lines.joined(separator: "\n")
    }
}
