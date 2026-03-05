import Foundation

public struct ScreenNavigator: Sendable {
    public var captureAll: @Sendable ([LassoConfig.Screen], UIAutomation, String) async throws -> [ScreenCapture]

    public init(
        captureAll: @escaping @Sendable ([LassoConfig.Screen], UIAutomation, String) async throws -> [ScreenCapture]
    ) {
        self.captureAll = captureAll
    }
}

// MARK: - Live

extension ScreenNavigator {
    public static let live = ScreenNavigator { screens, ui, outputDirectory in
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDirectory) {
            try fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        }

        // Freeze status bar for deterministic screenshots
        _ = try? await shell(
            "xcrun simctl status_bar \(ui.udid) override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4"
        )

        var captures: [ScreenCapture] = []

        for screen in screens {
            // Navigate to screen
            switch screen.path {
            case .launch:
                break // Already at launch screen
            case .steps(let steps):
                for step in steps {
                    if let label = step.tap {
                        try await ui.tap(label: label)
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    if let direction = step.swipe {
                        if let dir = SwipeDirection(rawValue: direction) {
                            try await ui.swipe(direction: dir)
                            try await Task.sleep(for: .milliseconds(300))
                        }
                    }
                }
            }

            // Wait for animations to settle
            try await Task.sleep(for: .milliseconds(500))

            // Take screenshot
            let data = try await ui.screenshot()
            let path = "\(outputDirectory)/\(screen.name).png"
            try data.write(to: URL(fileURLWithPath: path))

            captures.append(ScreenCapture(
                screenName: screen.name,
                path: path,
                sizeBytes: data.count
            ))
        }

        // Restore status bar
        _ = try? await shell("xcrun simctl status_bar \(ui.udid) clear")

        return captures
    }
}

// MARK: - Failing

extension ScreenNavigator {
    public static let failing = ScreenNavigator { _, _, _ in
        throw LassoError.commandFailed("ScreenNavigator.failing", 1)
    }
}
