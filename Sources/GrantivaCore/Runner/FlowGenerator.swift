import Foundation

/// Generates Maestro YAML flow files from grantiva.yml screen configs.
public enum FlowGenerator {
    /// Generate a single Maestro YAML flow that navigates all screens and takes screenshots.
    public static func generate(
        screens: [GrantivaConfig.Screen],
        bundleId: String
    ) -> String {
        var lines: [String] = []

        // Header
        lines.append("appId: \(bundleId)")
        lines.append("---")

        // launchApp creates the WDA session — required before any interaction
        lines.append("- launchApp")

        for screen in screens {
            switch screen.path {
            case .launch:
                lines.append("- takeScreenshot: \(screen.name)")

            case .steps(let steps):
                for step in steps {
                    if let label = step.tap {
                        lines.append("- tapOn: \"\(label)\"")
                    }
                    if let direction = step.swipe {
                        lines.append("- swipe:")
                        lines.append("    direction: \(maestroSwipeDirection(direction))")
                    }
                    if let text = step.type {
                        lines.append("- inputText: \"\(text)\"")
                    }
                    if let seconds = step.wait {
                        let ms = Int(seconds * 1000)
                        lines.append("- waitForAnimationToEnd:")
                        lines.append("    timeout: \(ms)")
                    }
                    if let label = step.assertVisible {
                        lines.append("- assertVisible: \"\(label)\"")
                    }
                    if let label = step.assertNotVisible {
                        lines.append("- assertNotVisible: \"\(label)\"")
                    }
                    if let path = step.runFlow {
                        lines.append("- runFlow: \"\(path)\"")
                    }
                }
                lines.append("- takeScreenshot: \(screen.name)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Write a flow to a temporary file, returning the path.
    public static func writeTemp(
        screens: [GrantivaConfig.Screen],
        bundleId: String
    ) throws -> String {
        let yaml = generate(screens: screens, bundleId: bundleId)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grantiva-flows")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let flowPath = tempDir.appendingPathComponent("flow.yaml").path
        try yaml.write(toFile: flowPath, atomically: true, encoding: .utf8)
        return flowPath
    }

    private static func maestroSwipeDirection(_ direction: String) -> String {
        switch direction.lowercased() {
        case "up": return "UP"
        case "down": return "DOWN"
        case "left": return "LEFT"
        case "right": return "RIGHT"
        default: return direction.uppercased()
        }
    }
}
