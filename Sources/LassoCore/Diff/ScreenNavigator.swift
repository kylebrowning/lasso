import Foundation
import Yams

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
            switch screen.path {
            case .launch:
                let result = StepResult(action: "Launch app", status: .passed, duration: 0)

                // Wait for animations to settle
                try await Task.sleep(for: .milliseconds(500))

                let data = try await ui.screenshot()
                let path = "\(outputDirectory)/\(screen.name).png"
                try data.write(to: URL(fileURLWithPath: path))

                captures.append(ScreenCapture(
                    screenName: screen.name, path: path,
                    sizeBytes: data.count, steps: [result]
                ))

            case .steps(let steps):
                let (stepResults, _) = await executeSteps(steps, ui: ui)

                // Wait for animations to settle
                try await Task.sleep(for: .milliseconds(500))

                // Take screenshot even if a step failed (shows actual state)
                let data = try await ui.screenshot()
                let path = "\(outputDirectory)/\(screen.name).png"
                try data.write(to: URL(fileURLWithPath: path))

                captures.append(ScreenCapture(
                    screenName: screen.name, path: path,
                    sizeBytes: data.count, steps: stepResults
                ))
            }
        }

        // Restore status bar
        _ = try? await shell("xcrun simctl status_bar \(ui.udid) clear")

        return captures
    }

    /// Execute a list of config steps, returning results and whether any step failed.
    @Sendable
    static func executeSteps(
        _ steps: [LassoConfig.Screen.Step],
        ui: UIAutomation
    ) async -> ([StepResult], Bool) {
        var results: [StepResult] = []
        var failed = false

        for step in steps {
            if failed { break }

            if let label = step.tap {
                let stepStart = Date()
                do {
                    let tree = try await ui.hierarchy()
                    if tree.find(label: label) != nil {
                        try await ui.tap(label: label)
                        try await Task.sleep(for: .milliseconds(500))
                        results.append(StepResult(
                            action: "Tap on \"\(label)\"", status: .passed,
                            duration: Date().timeIntervalSince(stepStart)
                        ))
                    } else {
                        results.append(StepResult(
                            action: "Tap on \"\(label)\"", status: .failed,
                            duration: Date().timeIntervalSince(stepStart),
                            message: "Element \"\(label)\" not found in hierarchy"
                        ))
                        failed = true
                    }
                } catch {
                    results.append(StepResult(
                        action: "Tap on \"\(label)\"", status: .failed,
                        duration: Date().timeIntervalSince(stepStart),
                        message: error.localizedDescription
                    ))
                    failed = true
                }
            }

            if failed { break }

            if let direction = step.swipe {
                let stepStart = Date()
                if let dir = SwipeDirection(rawValue: direction) {
                    do {
                        try await ui.swipe(direction: dir)
                        try await Task.sleep(for: .milliseconds(300))
                        results.append(StepResult(
                            action: "Swipe \(direction)", status: .passed,
                            duration: Date().timeIntervalSince(stepStart)
                        ))
                    } catch {
                        results.append(StepResult(
                            action: "Swipe \(direction)", status: .failed,
                            duration: Date().timeIntervalSince(stepStart),
                            message: error.localizedDescription
                        ))
                        failed = true
                    }
                } else {
                    results.append(StepResult(
                        action: "Swipe \(direction)", status: .failed, duration: 0,
                        message: "Invalid swipe direction: \(direction)"
                    ))
                    failed = true
                }
            }

            if failed { break }

            if let text = step.type {
                let stepStart = Date()
                do {
                    try await ui.type(text)
                    try await Task.sleep(for: .milliseconds(300))
                    results.append(StepResult(
                        action: "Type \"\(text)\"", status: .passed,
                        duration: Date().timeIntervalSince(stepStart)
                    ))
                } catch {
                    results.append(StepResult(
                        action: "Type \"\(text)\"", status: .failed,
                        duration: Date().timeIntervalSince(stepStart),
                        message: error.localizedDescription
                    ))
                    failed = true
                }
            }

            if failed { break }

            if let seconds = step.wait {
                let stepStart = Date()
                try? await Task.sleep(for: .seconds(seconds))
                results.append(StepResult(
                    action: "Wait \(seconds)s", status: .passed,
                    duration: Date().timeIntervalSince(stepStart)
                ))
            }

            if failed { break }

            if let label = step.assertVisible {
                let stepStart = Date()
                do {
                    let tree = try await ui.hierarchy()
                    let elapsed = Date().timeIntervalSince(stepStart)
                    if tree.find(label: label) != nil {
                        results.append(StepResult(
                            action: "Assert visible \"\(label)\"", status: .passed,
                            duration: elapsed
                        ))
                    } else {
                        results.append(StepResult(
                            action: "Assert visible \"\(label)\"", status: .failed,
                            duration: elapsed, message: "Element \"\(label)\" not visible"
                        ))
                        failed = true
                    }
                } catch {
                    results.append(StepResult(
                        action: "Assert visible \"\(label)\"", status: .failed,
                        duration: Date().timeIntervalSince(stepStart),
                        message: error.localizedDescription
                    ))
                    failed = true
                }
            }

            if failed { break }

            if let label = step.assertNotVisible {
                let stepStart = Date()
                do {
                    let tree = try await ui.hierarchy()
                    let elapsed = Date().timeIntervalSince(stepStart)
                    if tree.find(label: label) == nil {
                        results.append(StepResult(
                            action: "Assert not visible \"\(label)\"", status: .passed,
                            duration: elapsed
                        ))
                    } else {
                        results.append(StepResult(
                            action: "Assert not visible \"\(label)\"", status: .failed,
                            duration: elapsed,
                            message: "Element \"\(label)\" is visible but should not be"
                        ))
                        failed = true
                    }
                } catch {
                    results.append(StepResult(
                        action: "Assert not visible \"\(label)\"", status: .failed,
                        duration: Date().timeIntervalSince(stepStart),
                        message: error.localizedDescription
                    ))
                    failed = true
                }
            }

            if failed { break }

            if let flowPath = step.runFlow {
                let stepStart = Date()
                do {
                    let flowSteps = try loadFlowSteps(from: flowPath)
                    let (subResults, subFailed) = await executeSteps(flowSteps, ui: ui)
                    results.append(contentsOf: subResults)
                    if subFailed {
                        failed = true
                    } else {
                        results.append(StepResult(
                            action: "Run flow \"\(flowPath)\"", status: .passed,
                            duration: Date().timeIntervalSince(stepStart)
                        ))
                    }
                } catch {
                    results.append(StepResult(
                        action: "Run flow \"\(flowPath)\"", status: .failed,
                        duration: Date().timeIntervalSince(stepStart),
                        message: error.localizedDescription
                    ))
                    failed = true
                }
            }
        }

        return (results, failed)
    }
}

// MARK: - Flow Loading

/// Load steps from a flow YAML file. The file should contain an array of steps:
/// ```yaml
/// - tap: "Login"
/// - type: "user@example.com"
/// - tap: "Submit"
/// ```
func loadFlowSteps(from path: String) throws -> [LassoConfig.Screen.Step] {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw LassoError.invalidArgument("Flow file not found: \(path)")
    }
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = YAMLDecoder()
    return try decoder.decode([LassoConfig.Screen.Step].self, from: contents)
}

// MARK: - Failing

extension ScreenNavigator {
    public static let failing = ScreenNavigator { _, _, _ in
        throw LassoError.commandFailed("ScreenNavigator.failing", 1)
    }
}
