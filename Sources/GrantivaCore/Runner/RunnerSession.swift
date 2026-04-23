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
        outputDir: String = ".grantiva/captures",
        appFile: String? = nil,
        keepAlive: Bool = false,
        snapshot: String = "failure"
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
        // Defers fire in reverse order — trace must export before cleanup wipes
        // the report dir, so declare cleanup first, then the export.
        defer { try? FileManager.default.removeItem(atPath: reportDir) }
        defer {
            exportTraceArtifacts(
                reportDir: reportDir, outputDir: outputDir,
                snapshot: snapshot, flowName: "screens"
            )
        }

        // Freeze status bar for deterministic screenshots
        _ = try? await shell(
            "xcrun simctl status_bar \(udid) override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4"
        )
        defer {
            Task { _ = try? await shell("xcrun simctl status_bar \(udid) clear") }
        }

        // Run the runner
        // Global flags go before `test`, test flags after
        var args = [
            runnerBin,
            "--platform", "ios",
            "--device", udid,
            "--no-ansi",
            "--no-app-install",
        ]
        if let appFile {
            args += ["--app-file", appFile]
        }
        args += [
            "test",
            "--output", reportDir,
            "--flatten",
            "--wait-for-idle-timeout", "0",
            "--artifacts", runnerArtifactMode(for: snapshot),
        ]
        if keepAlive {
            args += ["--keep-alive"]
        }
        args += [flowPath]

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
        // Keep-alive sessions block waiting for SIGINT; a normal 5-minute cap
        // would kill them prematurely. Use an effectively-infinite timeout then.
        let timeoutSeconds: UInt64 = keepAlive ? 60 * 60 * 24 : 300
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

    /// Run a pre-existing Maestro YAML flow file directly, collecting any screenshots it takes.
    /// Throws on runner failure the same as `run()`.
    public static func runFlowFile(
        at flowPath: String,
        bundleId: String,
        udid: String,
        runner: RunnerManager = .live,
        outputDir: String = ".grantiva/captures",
        appFile: String? = nil,
        keepAlive: Bool = false,
        snapshot: String = "failure"
    ) async throws -> [ScreenCapture] {
        // Resolve relative paths against the working directory where the CLI was invoked,
        // not the runner binary's temp directory.
        let absoluteFlowPath: String
        if flowPath.hasPrefix("/") {
            absoluteFlowPath = flowPath
        } else {
            absoluteFlowPath = FileManager.default.currentDirectoryPath + "/" + flowPath
        }

        try await runner.ensureAvailable()

        let runnerBin = runner.runnerPath()
        let runnerDir = runner.runnerDir()

        // Inject the resolved bundleId as appId into the flow YAML so the runner can
        // launch the app even when flow files live in a subdirectory and don't have appId,
        // or when grantiva.yml is not co-located with the flow file.
        let originalContent = try String(contentsOfFile: absoluteFlowPath, encoding: .utf8)
        let injectedContent = injectAppId(originalContent, bundleId: bundleId)
        let originalFilename = URL(fileURLWithPath: absoluteFlowPath).lastPathComponent
        let tempFlowDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grantiva-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tempFlowDir, withIntermediateDirectories: true)
        let tempFlowPath = "\(tempFlowDir)/\(originalFilename)"
        try injectedContent.write(toFile: tempFlowPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFlowDir) }

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grantiva-report-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: reportDir, withIntermediateDirectories: true)
        // Defers fire in reverse order — trace must export before cleanup wipes
        // the report dir, so declare cleanup first, then the export.
        defer { try? FileManager.default.removeItem(atPath: reportDir) }
        defer {
            let flowName = URL(fileURLWithPath: flowPath).deletingPathExtension().lastPathComponent
            exportTraceArtifacts(
                reportDir: reportDir, outputDir: outputDir,
                snapshot: snapshot, flowName: flowName
            )
        }

        _ = try? await shell(
            "xcrun simctl status_bar \(udid) override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4"
        )
        defer {
            Task { _ = try? await shell("xcrun simctl status_bar \(udid) clear") }
        }

        var args = [
            runnerBin,
            "--platform", "ios",
            "--device", udid,
            "--no-ansi",
            "--no-app-install",
        ]
        if let appFile {
            args += ["--app-file", appFile]
        }
        args += [
            "test",
            "--output", reportDir,
            "--flatten",
            "--wait-for-idle-timeout", "0",
            "--artifacts", runnerArtifactMode(for: snapshot),
        ]
        if keepAlive {
            args += ["--keep-alive"]
        }
        args += [tempFlowPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runnerBin)
        process.arguments = Array(args.dropFirst())
        process.currentDirectoryURL = URL(fileURLWithPath: runnerDir)
        process.standardOutput = FileHandle.standardError
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()

        let stderrTask = Task<Data, Never> {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        // Keep-alive sessions block waiting for SIGINT; a normal 5-minute cap
        // would kill them prematurely. Use an effectively-infinite timeout then.
        let timeoutSeconds: UInt64 = keepAlive ? 60 * 60 * 24 : 300
        let pid = process.processIdentifier
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            if process.isRunning { kill(pid, SIGTERM) }
        }
        process.waitUntilExit()
        timeoutTask.cancel()

        let stderrData = await stderrTask.value
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let timedOut = process.terminationStatus == 15
            let reason = timedOut
                ? "Runner timed out after \(timeoutSeconds)s"
                : "Runner failed (exit \(process.terminationStatus))"
            throw GrantivaError.commandFailed(
                "\(reason):\n\(stderr.suffix(2000))",
                process.terminationStatus
            )
        }

        // Collect screenshots from runner output
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDir) {
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        let flowName = URL(fileURLWithPath: flowPath).deletingPathExtension().lastPathComponent
        let assetsDir = "\(reportDir)/assets"
        var captures: [ScreenCapture] = []

        if fm.fileExists(atPath: assetsDir) {
            let flowDirs = (try? fm.contentsOfDirectory(atPath: assetsDir)) ?? []
            let screenshotDir = flowDirs.first.map { "\(assetsDir)/\($0)" } ?? assetsDir
            let screenshotFiles = ((try? fm.contentsOfDirectory(atPath: screenshotDir)) ?? [])
                .filter { $0.hasSuffix(".png") }
                .sorted()

            for file in screenshotFiles {
                let screenshotName = "\(flowName)-\(URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent)"
                let srcPath = "\(screenshotDir)/\(file)"
                let dstPath = "\(outputDir)/\(screenshotName).png"
                if fm.fileExists(atPath: dstPath) { try fm.removeItem(atPath: dstPath) }
                try fm.copyItem(atPath: srcPath, toPath: dstPath)
                let data = try Data(contentsOf: URL(fileURLWithPath: dstPath))
                captures.append(ScreenCapture(
                    screenName: screenshotName,
                    path: dstPath,
                    sizeBytes: data.count,
                    steps: [StepResult(action: "Run flow \"\(flowName)\"", status: .passed, duration: 0)]
                ))
            }
        }

        // If the flow ran but took no screenshots, still report it as passed
        if captures.isEmpty {
            captures.append(ScreenCapture(
                screenName: flowName,
                path: "",
                sizeBytes: 0,
                steps: [StepResult(action: "Run flow \"\(flowName)\"", status: .passed, duration: 0)]
            ))
        }

        return captures
    }

    /// Maps the CLI-facing snapshot mode to the runner's `--artifacts` value.
    /// - `failure` → only capture on failure (runner's default behavior).
    /// - `trailing`, `full` → capture every step; the CLI trims post-run if needed.
    static func runnerArtifactMode(for snapshot: String) -> String {
        switch snapshot.lowercased() {
        case "trailing", "full", "always":
            return "always"
        case "never", "off", "none":
            return "never"
        default:
            return "failure"
        }
    }

    /// Copies the runner's per-step artifacts (PNG screenshots + XML hierarchy
    /// dumps) out of the temp report dir into a user-visible `trace/` folder,
    /// applying the snapshot policy.
    ///
    /// - `failure`: no trace/ files written. The simctl post-failure shot from
    ///   RunCommand is still captured separately.
    /// - `trailing`: keeps the failing step's artifacts plus the last successful
    ///   step's "after" screenshot — the "state going into the failure."
    /// - `full`: copies every captured artifact with a stable step-indexed name.
    ///
    /// Safe to call whether or not the runner succeeded. Best-effort: copy
    /// failures are logged to stderr but never thrown.
    static func exportTraceArtifacts(
        reportDir: String,
        outputDir: String,
        snapshot: String,
        flowName: String
    ) {
        let mode = snapshot.lowercased()
        guard mode == "trailing" || mode == "full" else { return }

        let fm = FileManager.default
        let assetsDir = "\(reportDir)/assets"
        guard fm.fileExists(atPath: assetsDir) else { return }

        // The runner writes assets/<flow-id>/cmd-NNN-<kind>-<timing>.png (and .xml).
        let flowDirs = (try? fm.contentsOfDirectory(atPath: assetsDir)) ?? []
        guard let flowSubdir = flowDirs.first else { return }
        let stepDir = "\(assetsDir)/\(flowSubdir)"

        let traceDir = "\(outputDir)/trace"
        if !fm.fileExists(atPath: traceDir) {
            try? fm.createDirectory(atPath: traceDir, withIntermediateDirectories: true)
        }

        let entries = (try? fm.contentsOfDirectory(atPath: stepDir)) ?? []
        let sorted = entries.sorted()

        // Parse cmd-NNN-... prefix so we can group by step and decide what to keep.
        struct StepArtifact {
            let file: String
            let index: Int
            let kind: String // "before", "after", or "" (hierarchy xml)
        }
        var artifacts: [StepArtifact] = []
        for name in sorted {
            guard name.hasPrefix("cmd-") else { continue }
            let stripped = String(name.dropFirst("cmd-".count))
            let parts = stripped.split(separator: "-", maxSplits: 1).map(String.init)
            guard let indexStr = parts.first, let idx = Int(indexStr) else { continue }
            let kind: String
            if name.hasSuffix("-before.png") {
                kind = "before"
            } else if name.hasSuffix("-after.png") {
                kind = "after"
            } else if name.hasSuffix(".xml") {
                kind = "xml"
            } else {
                kind = "other"
            }
            artifacts.append(StepArtifact(file: name, index: idx, kind: kind))
        }

        let maxIndex = artifacts.map { $0.index }.max() ?? 0
        let failingIndex = maxIndex // last captured step == last executed step

        let keep: [StepArtifact]
        switch mode {
        case "full":
            keep = artifacts
        case "trailing":
            // Failing step: all its artifacts. Previous step: just the "after"
            // shot — that's the "last good state" right before the failing step.
            keep = artifacts.filter { a in
                if a.index == failingIndex { return true }
                if a.index == failingIndex - 1 && a.kind == "after" { return true }
                return false
            }
        default:
            keep = []
        }

        for a in keep {
            let dst = "\(traceDir)/\(flowName)-\(a.file)"
            if fm.fileExists(atPath: dst) {
                try? fm.removeItem(atPath: dst)
            }
            do {
                try fm.copyItem(atPath: "\(stepDir)/\(a.file)", toPath: dst)
            } catch {
                FileHandle.standardError.write(Data("[grantiva] trace export failed for \(a.file): \(error)\n".utf8))
            }
        }
    }

    /// Injects or replaces the `appId` line in a Maestro flow YAML header.
    /// Flow files in subdirectories may omit appId or have it set to the wrong value;
    /// this ensures the runner always has the correct bundle ID for launchApp.
    static func injectAppId(_ content: String, bundleId: String) -> String {
        let lines = content.components(separatedBy: "\n")

        // Find --- document separator (not at line 0)
        var separatorIdx: Int?
        for (i, line) in lines.enumerated() where i > 0 {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                separatorIdx = i
                break
            }
        }

        if let idx = separatorIdx {
            var headerLines = Array(lines[0..<idx])
            if let appIdIdx = headerLines.firstIndex(where: { $0.hasPrefix("appId:") }) {
                headerLines[appIdIdx] = "appId: \(bundleId)"
            } else {
                headerLines.insert("appId: \(bundleId)", at: 0)
            }
            let bodyLines = Array(lines[idx...])
            return (headerLines + bodyLines).joined(separator: "\n")
        } else {
            // No separator: prepend header and separator before the command list
            return "appId: \(bundleId)\n---\n\(content)"
        }
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
