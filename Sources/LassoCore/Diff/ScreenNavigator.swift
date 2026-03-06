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
            var stepResults: [StepResult] = []
            var stepFailed = false

            switch screen.path {
            case .launch:
                stepResults.append(StepResult(
                    action: "Launch app",
                    status: .passed,
                    duration: 0
                ))
            case .steps(let steps):
                for step in steps {
                    if stepFailed { break }

                    if let label = step.tap {
                        let stepStart = Date()
                        do {
                            // Verify element exists before tapping
                            let tree = try await ui.hierarchy()
                            if tree.find(label: label) != nil {
                                try await ui.tap(label: label)
                                try await Task.sleep(for: .milliseconds(500))
                                let elapsed = Date().timeIntervalSince(stepStart)
                                stepResults.append(StepResult(
                                    action: "Tap on \"\(label)\"",
                                    status: .passed,
                                    duration: elapsed
                                ))
                            } else {
                                let elapsed = Date().timeIntervalSince(stepStart)
                                stepResults.append(StepResult(
                                    action: "Tap on \"\(label)\"",
                                    status: .failed,
                                    duration: elapsed,
                                    message: "Element \"\(label)\" not found in hierarchy"
                                ))
                                stepFailed = true
                            }
                        } catch {
                            let elapsed = Date().timeIntervalSince(stepStart)
                            stepResults.append(StepResult(
                                action: "Tap on \"\(label)\"",
                                status: .failed,
                                duration: elapsed,
                                message: error.localizedDescription
                            ))
                            stepFailed = true
                        }
                    }

                    if stepFailed { break }

                    if let direction = step.swipe {
                        let stepStart = Date()
                        if let dir = SwipeDirection(rawValue: direction) {
                            do {
                                try await ui.swipe(direction: dir)
                                try await Task.sleep(for: .milliseconds(300))
                                let elapsed = Date().timeIntervalSince(stepStart)
                                stepResults.append(StepResult(
                                    action: "Swipe \(direction)",
                                    status: .passed,
                                    duration: elapsed
                                ))
                            } catch {
                                let elapsed = Date().timeIntervalSince(stepStart)
                                stepResults.append(StepResult(
                                    action: "Swipe \(direction)",
                                    status: .failed,
                                    duration: elapsed,
                                    message: error.localizedDescription
                                ))
                                stepFailed = true
                            }
                        } else {
                            stepResults.append(StepResult(
                                action: "Swipe \(direction)",
                                status: .failed,
                                duration: 0,
                                message: "Invalid swipe direction: \(direction)"
                            ))
                            stepFailed = true
                        }
                    }

                    if stepFailed { break }

                    if let text = step.type {
                        let stepStart = Date()
                        do {
                            try await ui.type(text)
                            try await Task.sleep(for: .milliseconds(300))
                            let elapsed = Date().timeIntervalSince(stepStart)
                            stepResults.append(StepResult(
                                action: "Type \"\(text)\"",
                                status: .passed,
                                duration: elapsed
                            ))
                        } catch {
                            let elapsed = Date().timeIntervalSince(stepStart)
                            stepResults.append(StepResult(
                                action: "Type \"\(text)\"",
                                status: .failed,
                                duration: elapsed,
                                message: error.localizedDescription
                            ))
                            stepFailed = true
                        }
                    }

                    if stepFailed { break }

                    if let label = step.assertVisible {
                        let stepStart = Date()
                        do {
                            let tree = try await ui.hierarchy()
                            let elapsed = Date().timeIntervalSince(stepStart)
                            if tree.find(label: label) != nil {
                                stepResults.append(StepResult(
                                    action: "Assert visible \"\(label)\"",
                                    status: .passed,
                                    duration: elapsed
                                ))
                            } else {
                                stepResults.append(StepResult(
                                    action: "Assert visible \"\(label)\"",
                                    status: .failed,
                                    duration: elapsed,
                                    message: "Element \"\(label)\" not visible"
                                ))
                                stepFailed = true
                            }
                        } catch {
                            let elapsed = Date().timeIntervalSince(stepStart)
                            stepResults.append(StepResult(
                                action: "Assert visible \"\(label)\"",
                                status: .failed,
                                duration: elapsed,
                                message: error.localizedDescription
                            ))
                            stepFailed = true
                        }
                    }
                }
            }

            // Wait for animations to settle
            try await Task.sleep(for: .milliseconds(500))

            // Take screenshot even if a step failed (shows actual state)
            let data = try await ui.screenshot()
            let path = "\(outputDirectory)/\(screen.name).png"
            try data.write(to: URL(fileURLWithPath: path))

            captures.append(ScreenCapture(
                screenName: screen.name,
                path: path,
                sizeBytes: data.count,
                steps: stepResults
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
