import Foundation
import Yams

public struct ScriptResult: Sendable, Codable {
    public let steps: [StepResult]
    public let duration: Double

    public struct StepResult: Sendable, Codable {
        public let step: String
        public let status: String
        public let error: String?
        public let screenshotPath: String?
    }
}

public struct ScriptRunner: Sendable {
    public init() {}

    public func run(
        steps: [ScriptStep],
        ui: UIAutomation,
        outputDir: String? = nil,
        log: @Sendable (String) -> Void = { _ in }
    ) async throws -> ScriptResult {
        let start = CFAbsoluteTimeGetCurrent()
        var results: [ScriptResult.StepResult] = []

        for (i, step) in steps.enumerated() {
            log("[\(i + 1)/\(steps.count)] \(step.description)")

            do {
                var screenshotPath: String? = nil

                switch step {
                case .tap(let label):
                    try await ui.tap(label: label)

                case .tapCoordinate(let x, let y):
                    try await ui.tap(x: x, y: y)

                case .swipe(let direction):
                    guard let dir = SwipeDirection(rawValue: direction) else {
                        throw LassoError.invalidArgument("Invalid swipe direction: \(direction). Use: up, down, left, right")
                    }
                    try await ui.swipe(direction: dir)

                case .type(let text):
                    try await ui.type(text)

                case .wait(let seconds):
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

                case .screenshot(let name):
                    let data = try await ui.screenshot()
                    if let dir = outputDir {
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: dir) {
                            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        }
                        let filename = (name ?? "step_\(i + 1)") + ".png"
                        let path = (dir as NSString).appendingPathComponent(filename)
                        try data.write(to: URL(fileURLWithPath: path))
                        screenshotPath = path
                        log("  Saved: \(path)")
                    }

                case .back:
                    // Swipe from left edge to simulate back navigation
                    try await ui.swipe(startX: 5, startY: 400, endX: 300, endY: 400)

                case .assertVisible(let label):
                    let tree = try await ui.hierarchy()
                    guard tree.find(label: label) != nil else {
                        throw LassoError.invalidArgument("Assertion failed: \"\(label)\" is not visible")
                    }

                case .assertNotVisible(let label):
                    let tree = try await ui.hierarchy()
                    if tree.find(label: label) != nil {
                        throw LassoError.invalidArgument("Assertion failed: \"\(label)\" is visible but should not be")
                    }

                case .runFlow(let path):
                    let flowSteps = try loadFlowAsScriptSteps(from: path)
                    log("  Running \(flowSteps.count) step(s) from \(path)")
                    let subResult = try await run(steps: flowSteps, ui: ui, outputDir: outputDir, log: log)
                    results.append(contentsOf: subResult.steps)
                }

                results.append(.init(step: step.description, status: "ok", error: nil, screenshotPath: screenshotPath))
            } catch {
                let msg = error.localizedDescription
                log("  Error: \(msg)")
                results.append(.init(step: step.description, status: "error", error: msg, screenshotPath: nil))
                throw error
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - start
        return ScriptResult(steps: results, duration: duration)
    }
}

// MARK: - Flow Loading

extension ScriptRunner {
    func loadFlowAsScriptSteps(from path: String) throws -> [ScriptStep] {
        try loadFlowSteps(from: path).compactMap { $0.toScriptStep() }
    }
}

// MARK: - Config Step → ScriptStep Conversion

extension LassoConfig.Screen.Step {
    /// Convert a YAML config step to a ScriptStep for execution.
    public func toScriptStep() -> ScriptStep? {
        if let label = tap { return .tap(label: label) }
        if let direction = swipe { return .swipe(direction: direction) }
        if let text = type { return .type(text: text) }
        if let seconds = wait { return .wait(seconds: seconds) }
        if let label = assertVisible { return .assertVisible(label: label) }
        if let label = assertNotVisible { return .assertNotVisible(label: label) }
        if let path = runFlow { return .runFlow(path: path) }
        return nil
    }
}
