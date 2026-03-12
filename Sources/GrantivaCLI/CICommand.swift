import ArgumentParser
import Foundation
import GrantivaCore
import GrantivaAPI

struct CICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ci",
        abstract: "CI pipeline — capture, compare, and upload results.",
        subcommands: [CIRunCommand.self]
    )

    // MARK: - ci run

    struct CIRunCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run full CI pipeline: capture screenshots, compare against baselines, upload results."
        )

        @OptionGroup var options: GlobalOptions
        @OptionGroup var buildOptions: BuildOptions

        @Option(name: .long, help: "Scheme to build")
        var scheme: String?

        @Option(name: .long, help: "Simulator name")
        var simulator: String?

        @Option(name: .long, help: "Bundle identifier")
        var bundleId: String?

        var simulatorManager: SimulatorManager = .live
        var driverCache: DriverCache = .live
        var imageDiffer: ImageDiffer = .live

        /// Log a step to stderr and stream to the backend if a run is active.
        func log(_ message: String, client: RangeClient? = nil, project: String? = nil, runId: String? = nil) {
            guard !options.json else { return }
            let line = "[grantiva] \(message)"
            FileHandle.standardError.write(Data("\(line)\n".utf8))

            // Fire-and-forget log append to backend
            if let client, let project, let runId {
                Task {
                    try? await client.appendLog(project, runId, line)
                }
            }
        }

        func run() async throws {
            let config = try? GrantivaConfig.load()
            let captureDir = ".grantiva/captures"
            let diffDir = ".grantiva/captures/diffs"
            let start = Date()

            // Resolve app binary first (if --app-file provided) so we can derive bundle ID
            let resolvedBinary = try buildOptions.resolveAppBinary()
            defer { resolvedBinary?.cleanup() }

            let appBundleId = resolvedBinary.flatMap { AppBinaryResolver.bundleId(from: $0.appPath) }

            // Resolve project
            let resolved = try await ResolvedProject.resolve(
                schemeFlag: scheme, simulatorFlag: simulator, bundleIdFlag: bundleId, config: config,
                skipBuild: buildOptions.shouldSkipBuild,
                appBundleId: appBundleId
            )
            log("Resolved: scheme=\(resolved.scheme ?? "(none)") simulator=\(resolved.simulator) screens=\(resolved.screens.count)")

            guard !resolved.screens.isEmpty else {
                throw GrantivaError.invalidArgument("No screens configured in grantiva.yml")
            }

            // Must be authenticated for CI
            guard let credentials = AuthStore.resolveCredentials() else {
                throw GrantivaError.notAuthenticated
            }
            log("Authenticated with \(credentials.baseURL)")

            let client = RangeClient(apiKey: credentials.apiKey, baseURL: credentials.baseURL)
            let projectId = try await ProjectIdentifier.resolve()
            let project = projectId.projectSlug
            let branch = projectId.currentBranch
            log("Project: \(project) Branch: \(branch)")

            // Get commit SHA (best effort)
            let commitSHA = try? await shell("git rev-parse HEAD")
            let trimmedSHA = commitSHA?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Determine trigger
            let trigger = ProcessInfo.processInfo.environment["CI"] != nil ? "ci" : "manual"

            // Start run immediately so it appears in the dashboard as "running"
            let startResponse = try await client.startRun(project, StartRunRequest(
                branch: branch, commitSHA: trimmedSHA, trigger: trigger
            ))
            let runId = startResponse.runId
            log("Run started: \(runId)", client: client, project: project, runId: runId)

            // Helper to log with streaming
            func rlog(_ message: String) {
                log(message, client: client, project: project, runId: runId)
            }

            do {
                // 0. Preflight: ensure driver is available before expensive build
                let driverCacheValid = await driverCache.isValid()
                rlog("Driver cache valid: \(driverCacheValid)")
                if !driverCacheValid {
                    rlog("Preparing driver cache...")
                    try await driverCache.buildAndCache(resolved.simulator)
                    rlog("Driver cache ready")
                }

                // 1. Boot → Build → Install → Launch → Capture
                rlog("Booting simulator: \(resolved.simulator)")
                let device = try await simulatorManager.boot(nameOrUDID: resolved.simulator)
                rlog("Simulator booted: \(device.name) (\(device.udid))")
                let destination = "platform=iOS Simulator,name=\(device.name)"

                var productPath: String?

                if buildOptions.shouldSkipInstall {
                    rlog("Skipping build and install (--no-build)")
                } else if let resolvedBinary {
                    rlog("Using pre-built binary: \(URL(fileURLWithPath: resolvedBinary.appPath).lastPathComponent)")
                    productPath = resolvedBinary.appPath
                } else {
                    guard let buildScheme = resolved.scheme else {
                        throw GrantivaError.invalidArgument(
                            "No scheme specified. Pass --scheme, set it in grantiva.yml, or use --app-file to provide a pre-built binary."
                        )
                    }

                    rlog("Building \(buildScheme)...")

                    let buildResult = try await XcodeBuildRunner().build(
                        scheme: buildScheme,
                        workspace: resolved.workspace,
                        project: resolved.project,
                        destination: destination
                    )
                    rlog("Build finished: success=\(buildResult.success) duration=\(String(format: "%.1fs", buildResult.duration))")

                    guard buildResult.success else {
                        if options.json {
                            print(try JSONOutput.string(buildResult))
                        } else {
                            print(TableFormatter().formatBuild(buildResult))
                        }
                        throw ExitCode.failure
                    }
                    productPath = buildResult.productPath
                }

                if !buildOptions.shouldSkipInstall, let bid = resolved.bundleId {
                    if let productPath {
                        rlog("Installing \(bid)...")
                        try await XcodeBuildRunner().install(
                            bundleId: bid, productPath: productPath, udid: device.udid
                        )
                    }
                    rlog("Launching \(bid)...")
                    try await XcodeBuildRunner().launch(bundleId: bid, udid: device.udid)
                    try await Task.sleep(for: .seconds(2))
                }

                // Start driver (needed for screenshots on headless CI + navigation)
                rlog("Starting driver on port \(options.driverPort)...")
                let session = try await DriverSession.start(
                    udid: device.udid,
                    bundleId: resolved.bundleId,
                    simulatorName: device.name,
                    port: options.driverPort,
                    cache: driverCache
                )
                rlog("Driver healthy")

                defer {
                    Task { await session.stop() }
                }

                rlog("Capturing \(resolved.screens.count) screen(s)...")

                let screenCaptures = try await session.captureAll(resolved.screens, captureDir)
                rlog("Capture complete")

                // Print step-by-step results (Maestro-style)
                if !options.json {
                    for capture in screenCaptures {
                        FileHandle.standardError.write(Data("\n  \(capture.screenName)\n".utf8))
                        for step in capture.steps {
                            let icon = step.status == .passed ? "\u{2713}" : "\u{2717}"
                            let line = "    \(icon) \(step.action)"
                            FileHandle.standardError.write(Data("\(line)\n".utf8))
                            if let msg = step.message {
                                FileHandle.standardError.write(Data("      \(msg)\n".utf8))
                            }
                        }
                    }
                    FileHandle.standardError.write(Data("\n".utf8))
                }

                // Build step uploads lookup by screen name
                var stepsByScreen: [String: [RunStepUpload]] = [:]
                for capture in screenCaptures {
                    stepsByScreen[capture.screenName] = capture.steps.map { step in
                        RunStepUpload(
                            action: step.action,
                            status: step.status.rawValue,
                            duration: step.duration,
                            message: step.message
                        )
                    }
                }

                // 2. Compare against baselines
                let diffConfig = config?.diff ?? .init()
                let fm = FileManager.default
                let store = client.asBaselineStore(project: project, branch: branch)
                let differ = imageDiffer

                if !fm.fileExists(atPath: diffDir) {
                    try fm.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
                }

                guard fm.fileExists(atPath: captureDir) else {
                    throw GrantivaError.noCaptures(captureDir)
                }
                let captureFiles = try fm.contentsOfDirectory(atPath: captureDir)
                    .filter { $0.hasSuffix(".png") }
                    .sorted()

                guard !captureFiles.isEmpty else {
                    throw GrantivaError.noCaptures(captureDir)
                }

                rlog("Comparing \(captureFiles.count) screen(s) against baselines...")

                var screenUploads: [RunScreenUpload] = []
                var allPassed = true

                for file in captureFiles {
                    let screenName = String(file.dropLast(4))
                    let capturePath = "\(captureDir)/\(file)"
                    let captureData = try Data(contentsOf: URL(fileURLWithPath: capturePath))

                    let baselineData = try await store.load(screenName)

                    if let baselineData {
                        do {
                            let output = try differ.compare(baselineData, captureData)
                            let pixelPass = output.pixelDiffPercent <= diffConfig.threshold
                            let perceptualPass = output.perceptualDistance <= diffConfig.perceptualThreshold
                            let passed = pixelPass && perceptualPass

                            var diffData: Data? = nil
                            if !passed {
                                allPassed = false
                                let path = "\(diffDir)/\(screenName)_diff.png"
                                try output.diffImageData.write(to: URL(fileURLWithPath: path))
                                diffData = output.diffImageData
                            }

                            let message = passed
                                ? "Passed"
                                : "Failed: pixel=\(String(format: "%.2f%%", output.pixelDiffPercent * 100)) perceptual=\(String(format: "%.1f", output.perceptualDistance))"

                            screenUploads.append(RunScreenUpload(
                                name: screenName,
                                status: passed ? "passed" : "failed",
                                pixelDiffPercent: output.pixelDiffPercent,
                                perceptualDistance: output.perceptualDistance,
                                pixelThreshold: diffConfig.threshold,
                                perceptualThreshold: diffConfig.perceptualThreshold,
                                message: message,
                                captureData: captureData,
                                diffData: diffData,
                                steps: stepsByScreen[screenName] ?? []
                            ))
                        } catch {
                            allPassed = false
                            screenUploads.append(RunScreenUpload(
                                name: screenName,
                                status: "error",
                                pixelThreshold: diffConfig.threshold,
                                perceptualThreshold: diffConfig.perceptualThreshold,
                                message: "Error: \(error.localizedDescription)",
                                captureData: captureData,
                                steps: stepsByScreen[screenName] ?? []
                            ))
                        }
                    } else {
                        // New screen — no baseline
                        screenUploads.append(RunScreenUpload(
                            name: screenName,
                            status: "new_screen",
                            pixelThreshold: diffConfig.threshold,
                            perceptualThreshold: diffConfig.perceptualThreshold,
                            message: "New screen — no baseline",
                            captureData: captureData,
                            steps: stepsByScreen[screenName] ?? []
                        ))
                    }
                }

                // 3. Complete run with results
                let duration = Date().timeIntervalSince(start)
                let upload = RunUpload(
                    branch: branch,
                    commitSHA: trimmedSHA,
                    trigger: trigger,
                    duration: duration,
                    screens: screenUploads
                )

                rlog("Uploading results to \(credentials.baseURL)...")

                let runResponse = try await client.completeRun(project, runId, upload)
                rlog("Upload complete: run=\(runResponse.runId)")

                // 4. Output results
                struct CIRunResult: Codable, Sendable {
                    let runId: String
                    let status: String
                    let url: String
                    let branch: String
                    let commitSha: String?
                    let trigger: String
                    let screenCount: Int
                    let passedCount: Int
                    let failedCount: Int
                    let newCount: Int
                    let duration: Double

                    enum CodingKeys: String, CodingKey {
                        case runId = "run_id"
                        case status, url, branch, trigger, duration
                        case commitSha = "commit_sha"
                        case screenCount = "screen_count"
                        case passedCount = "passed_count"
                        case failedCount = "failed_count"
                        case newCount = "new_count"
                    }
                }

                let result = CIRunResult(
                    runId: runResponse.runId,
                    status: runResponse.status,
                    url: runResponse.url,
                    branch: branch,
                    commitSha: trimmedSHA,
                    trigger: trigger,
                    screenCount: runResponse.screenCount,
                    passedCount: runResponse.passedCount,
                    failedCount: runResponse.failedCount,
                    newCount: runResponse.newCount,
                    duration: duration
                )

                if options.json {
                    print(try JSONOutput.string(result))
                } else {
                    print("")
                    print("  Run:      \(result.runId)")
                    print("  Status:   \(result.status)")
                    print("  Branch:   \(result.branch)")
                    if let sha = result.commitSha {
                        print("  Commit:   \(String(sha.prefix(8)))")
                    }
                    print("  Trigger:  \(result.trigger)")
                    print("  Screens:  \(result.screenCount) total, \(result.passedCount) passed, \(result.failedCount) failed, \(result.newCount) new")
                    print("  Duration: \(String(format: "%.1fs", result.duration))")
                    print("  URL:      \(result.url)")
                    print("")
                }

                if !allPassed {
                    throw ExitCode.failure
                }
            } catch {
                // If the run was started but failed, try to mark it as failed
                try? await client.appendLog(project, runId, "[grantiva] Run failed: \(error)")
                throw error
            }
        }
    }
}
