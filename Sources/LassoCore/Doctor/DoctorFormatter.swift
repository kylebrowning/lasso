import Foundation

public struct DoctorFormatter: Sendable {
    public init() {}

    public func format(_ checks: [DoctorCheck]) -> String {
        var lines: [String] = []

        lines.append("")
        lines.append("  Lasso Doctor")
        lines.append("  " + String(repeating: "─", count: 50))

        let sections: [DoctorCheck.Section] = [.required, .project, .cloud]

        for section in sections {
            let sectionChecks = checks.filter { $0.section == section }
            guard !sectionChecks.isEmpty else { continue }

            lines.append("")
            lines.append("  \(section.rawValue)")
            lines.append("")

            let maxName = sectionChecks.map(\.name.count).max() ?? 0

            for check in sectionChecks {
                let icon: String
                switch check.status {
                case .ok:      icon = "\u{001B}[32m✓\u{001B}[0m"
                case .warning: icon = "\u{001B}[33m●\u{001B}[0m"
                case .error:   icon = "\u{001B}[31m✗\u{001B}[0m"
                }
                let padded = check.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
                let msg: String
                switch check.status {
                case .ok:      msg = check.message
                case .warning: msg = "\u{001B}[33m\(check.message)\u{001B}[0m"
                case .error:   msg = "\u{001B}[31m\(check.message)\u{001B}[0m"
                }
                lines.append("    \(icon) \(padded)  \(msg)")
                if let fix = check.fix {
                    let padding = String(repeating: " ", count: maxName + 6)
                    lines.append("    \(padding)\u{001B}[2m\(fix)\u{001B}[0m")
                }
            }
        }

        let errors = checks.filter { $0.status == .error }.count
        let warnings = checks.filter { $0.status == .warning }.count
        let ok = checks.filter { $0.status == .ok }.count

        lines.append("")
        lines.append("  " + String(repeating: "─", count: 50))

        var summary: [String] = []
        if ok > 0 { summary.append("\u{001B}[32m\(ok) passed\u{001B}[0m") }
        if warnings > 0 { summary.append("\u{001B}[33m\(warnings) optional\u{001B}[0m") }
        if errors > 0 { summary.append("\u{001B}[31m\(errors) failed\u{001B}[0m") }
        lines.append("  \(summary.joined(separator: " · "))")
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
