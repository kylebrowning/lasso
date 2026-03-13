import Foundation

/// Orchestrates the grantiva-runner execution and collects screenshot results.
public enum RunnerSession {
    /// Run the embedded runner against a booted simulator.
    /// Generates a Maestro flow, executes it, and collects screenshots.
    public static func run(
        screens: [GrantivaConfig.Screen],
        bundleId: String,
        udid: String,
        runner: RunnerManager = .live,
        outputDir: String = ".grantiva/captures"
    ) async throws -> [ScreenCapture] {
        // Ensure runner is extracted
        try await runner.ensureAvailable()

        let runnerBin = runner.runnerPath()
        let runnerDir = runner.runnerDir()

        // Generate Maestro flow YAML
        let flowPath = try FlowGenerator.writeTemp(screens: screens, bundleId: bundleId)
        defer { try? FileManager.default.removeItem(atPath: flowPath) }

        // Create a temp directory for runner reports
        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grantiva-report-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: reportDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: reportDir) }

        // Freeze status bar for deterministic screenshots
        _ = try? await shell(
            "xcrun simctl status_bar \(udid) override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4"
        )
        defer {
            Task { _ = try? await shell("xcrun simctl status_bar \(udid) clear") }
        }

        // Run the runner
        // Global flags go before `test`, test flags after
        let args = [
            runnerBin,
            "--platform", "ios",
            "--device", udid,
            "--no-ansi",
            "--no-app-install",
            "test",
            "--output", reportDir,
            "--flatten",
            "--wait-for-idle-timeout", "0",
            flowPath,
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runnerBin)
        process.arguments = Array(args.dropFirst()) // drop the binary path
        process.currentDirectoryURL = URL(fileURLWithPath: runnerDir)

        // Stream stdout to stderr so CI sees runner progress in real time
        // Capture stderr separately for error reporting
        process.standardOutput = FileHandle.standardError
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()

        // Read stderr in background to avoid pipe buffer deadlock
        let stderrTask = Task<Data, Never> {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        // Timeout: kill the runner if it takes longer than 5 minutes
        let timeoutSeconds: UInt64 = 300
        let pid = process.processIdentifier
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            if process.isRunning {
                kill(pid, SIGTERM)
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stderrData = await stderrTask.value
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let output = stderr
            let timedOut = process.terminationStatus == 15 // SIGTERM
            let reason = timedOut
                ? "Runner timed out after \(timeoutSeconds)s"
                : "Runner failed (exit \(process.terminationStatus))"
            throw GrantivaError.commandFailed(
                "\(reason):\n\(output.suffix(2000))",
                process.terminationStatus
            )
        }

        // Collect screenshots from report output
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDir) {
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        // The runner saves takeScreenshot outputs in assets/<flow-id>/cmd-NNN-<name>.png
        // Find the assets directory
        let assetsDir = "\(reportDir)/assets"
        var captures: [ScreenCapture] = []

        if fm.fileExists(atPath: assetsDir) {
            // Find the single flow subdirectory
            let flowDirs = (try? fm.contentsOfDirectory(atPath: assetsDir)) ?? []
            let screenshotDir = flowDirs.first.map { "\(assetsDir)/\($0)" } ?? assetsDir

            // Map screen names to their expected screenshot files
            for screen in screens {
                let pattern = screen.name
                let screenshotFiles = ((try? fm.contentsOfDirectory(atPath: screenshotDir)) ?? [])
                    .filter { $0.contains(pattern) && $0.hasSuffix(".png") }
                    .sorted()

                if let file = screenshotFiles.first {
                    let srcPath = "\(screenshotDir)/\(file)"
                    let dstPath = "\(outputDir)/\(screen.name).png"
                    if fm.fileExists(atPath: dstPath) {
                        try fm.removeItem(atPath: dstPath)
                    }
                    try fm.copyItem(atPath: srcPath, toPath: dstPath)

                    let data = try Data(contentsOf: URL(fileURLWithPath: dstPath))
                    let steps = buildStepResults(for: screen)
                    captures.append(ScreenCapture(
                        screenName: screen.name, path: dstPath,
                        sizeBytes: data.count, steps: steps
                    ))
                } else {
                    // Screenshot not found — report as failed
                    captures.append(ScreenCapture(
                        screenName: screen.name, path: "",
                        sizeBytes: 0, steps: [
                            StepResult(
                                action: "Take screenshot",
                                status: .failed, duration: 0,
                                message: "Screenshot not found in runner output"
                            ),
                        ]
                    ))
                }
            }
        } else {
            // Fallback: try parsing runner stdout for screenshot paths
            throw GrantivaError.commandFailed(
                "Runner completed but no screenshots found in \(assetsDir)",
                1
            )
        }

        return captures
    }

    /// Build synthetic step results from the screen config.
    private static func buildStepResults(for screen: GrantivaConfig.Screen) -> [StepResult] {
        switch screen.path {
        case .launch:
            return [StepResult(action: "Launch app", status: .passed, duration: 0)]
        case .steps(let steps):
            return steps.map { step in
                let action: String
                if let label = step.tap {
                    action = "Tap on \"\(label)\""
                } else if let direction = step.swipe {
                    action = "Swipe \(direction)"
                } else if let text = step.type {
                    action = "Type \"\(text)\""
                } else if let seconds = step.wait {
                    action = "Wait \(seconds)s"
                } else if let label = step.assertVisible {
                    action = "Assert visible \"\(label)\""
                } else if let label = step.assertNotVisible {
                    action = "Assert not visible \"\(label)\""
                } else if let path = step.runFlow {
                    action = "Run flow \"\(path)\""
                } else {
                    action = "Unknown step"
                }
                return StepResult(action: action, status: .passed, duration: 0)
            }
        }
    }
}
