import Foundation

public struct TableFormatter: Sendable {
    public init() {}

    public func formatDevices(_ devices: [SimulatorDevice]) -> String {
        guard !devices.isEmpty else { return "No simulators found." }
        var lines: [String] = []
        let maxName = max(devices.map(\.name.count).max() ?? 0, 4)
        let header = "Name".padding(toLength: maxName, withPad: " ", startingAt: 0) + "  State     Runtime"
        lines.append(header)
        lines.append(String(repeating: "─", count: header.count + 10))
        for device in devices {
            let name = device.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
            let state = device.isBooted ? "Booted  " : "Shutdown"
            lines.append("\(name)  \(state)  \(device.runtime)")
        }
        return lines.joined(separator: "\n")
    }

    public func formatBuild(_ result: BuildResult) -> String {
        var lines: [String] = []
        lines.append(result.success ? "✓ Build succeeded" : "✗ Build failed")
        lines.append("  Scheme: \(result.scheme)")
        lines.append("  Duration: \(String(format: "%.1f", result.duration))s")
        if !result.warnings.isEmpty {
            lines.append("  Warnings: \(result.warnings.count)")
        }
        if !result.errors.isEmpty {
            for error in result.errors.prefix(5) {
                lines.append("  ✗ \(error)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public func formatTests(_ result: TestResult) -> String {
        var lines: [String] = []
        lines.append(result.success ? "✓ Tests passed" : "✗ Tests failed")
        lines.append("  Scheme: \(result.scheme)")
        lines.append("  Duration: \(String(format: "%.1f", result.duration))s")
        lines.append("  Passed: \(result.testsPassed)  Failed: \(result.testsFailed)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Diff

    public func formatCapture(_ result: CaptureResult) -> String {
        var lines: [String] = []
        lines.append("Captured \(result.screens.count) screen\(result.screens.count == 1 ? "" : "s") in \(String(format: "%.1f", result.duration))s")
        lines.append("  Directory: \(result.directory)")
        for screen in result.screens {
            let kb = String(format: "%.1f", Double(screen.sizeBytes) / 1024.0)
            lines.append("  • \(screen.screenName) (\(kb) KB)")
        }
        return lines.joined(separator: "\n")
    }

    public func formatCompare(_ result: CompareResult) -> String {
        var lines: [String] = []
        let passCount = result.screens.filter { $0.status == .passed }.count
        let failCount = result.screens.filter { $0.status == .failed }.count
        let newCount = result.screens.filter { $0.status == .newScreen }.count
        let errCount = result.screens.filter { $0.status == .error }.count

        lines.append(result.passed ? "✓ Visual diff passed" : "✗ Visual diff failed")
        lines.append("  Duration: \(String(format: "%.1f", result.duration))s")
        lines.append("  Passed: \(passCount)  Failed: \(failCount)  New: \(newCount)  Errors: \(errCount)")
        lines.append("")
        for screen in result.screens {
            let icon: String
            switch screen.status {
            case .passed: icon = "✓"
            case .failed: icon = "✗"
            case .newScreen: icon = "?"
            case .error: icon = "!"
            }
            var detail = "\(icon) \(screen.screenName)"
            if let pct = screen.pixelDiffPercent {
                detail += "  pixel=\(String(format: "%.2f%%", pct * 100))"
            }
            if let dist = screen.perceptualDistance {
                detail += "  perceptual=\(String(format: "%.1f", dist))"
            }
            lines.append(detail)
            if screen.status != .passed {
                lines.append("    \(screen.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public func formatApprove(_ result: ApproveResult) -> String {
        var lines: [String] = []
        lines.append("Approved \(result.approvedScreens.count) screen\(result.approvedScreens.count == 1 ? "" : "s") as baseline")
        lines.append("  Directory: \(result.baselineDirectory)")
        for name in result.approvedScreens {
            lines.append("  • \(name)")
        }
        return lines.joined(separator: "\n")
    }
}
