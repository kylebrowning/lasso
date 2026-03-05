import ArgumentParser
import Foundation
import LassoCore
import LassoRange

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

        func run() async throws {
            let config = try? LassoConfig.load()
            let captureDir = ".lasso/captures"
            let diffDir = ".lasso/captures/diffs"
            let start = Date()

            // Resolve project
            let resolved = try await ResolvedProject.resolve(
                schemeFlag: scheme, simulatorFlag: simulator, bundleIdFlag: bundleId, config: config
            )

            guard !resolved.screens.isEmpty else {
                throw LassoError.invalidArgument("No screens configured in lasso.yml")
            }

            // Must be authenticated for CI
            guard let credentials = AuthStore.resolveCredentials() else {
                throw LassoError.notAuthenticated
            }

            let client = RangeClient.live(apiKey: credentials.apiKey, baseURL: credentials.baseURL)
            let identifier = ProjectIdentifier.live
            let project = try await identifier.projectSlug()
            let branch = try await identifier.currentBranch()

            // Get commit SHA (best effort)
            let commitSHA = try? await shell("git rev-parse HEAD")

            // Determine trigger
            let trigger = ProcessInfo.processInfo.environment["CI"] != nil ? "ci" : "manual"

            // 1. Boot → Build → Install → Launch → Capture
            let device = try await SimulatorManager().boot(nameOrUDID: resolved.simulator)
            let destination = "platform=iOS Simulator,name=\(device.name)"

            var productPath: String?

            if let resolved_path = try await buildOptions.resolveProductPath(
                scheme: resolved.scheme, workspace: resolved.workspace,
                project: resolved.project, destination: destination
            ) {
                if !options.json {
                    print("Skipping build — using \(resolved_path)")
                }
                productPath = resolved_path
            } else {
                if !options.json {
                    print("Building \(resolved.scheme)...")
                }

                let buildResult = try await XcodeBuildRunner().build(
                    scheme: resolved.scheme,
                    workspace: resolved.workspace,
                    project: resolved.project,
                    destination: destination
                )

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

            if let bid = resolved.bundleId {
                if let productPath {
                    try await XcodeBuildRunner().install(
                        bundleId: bid, productPath: productPath, udid: device.udid
                    )
                }
                try await XcodeBuildRunner().launch(bundleId: bid, udid: device.udid)
                try await Task.sleep(for: .seconds(2))
            }

            // Start driver if needed
            var driverManager: DriverManager?
            if resolved.screens.hasNavigationSteps {
                let driverConfig = DriverConfig(
                    targetBundleId: resolved.bundleId,
                    simulatorName: device.name,
                    port: options.driverPort
                )
                let manager = DriverManager.live()
                if !options.json {
                    print("Starting driver for navigation...")
                }
                try await manager.start(driverConfig)
                driverManager = manager
            }

            defer {
                if let manager = driverManager {
                    Task { try? await manager.stop() }
                }
            }

            if !options.json {
                print("Capturing \(resolved.screens.count) screen(s)...")
            }

            let ui = options.makeUIAutomation(udid: device.udid)
            _ = try await ScreenNavigator.live.captureAll(resolved.screens, ui, captureDir)

            // 2. Compare against baselines
            let diffConfig = config?.diff ?? .init()
            let fm = FileManager.default
            let store = client.asBaselineStore(project: project, branch: branch)
            let differ = ImageDiffer.live

            if !fm.fileExists(atPath: diffDir) {
                try fm.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
            }

            guard fm.fileExists(atPath: captureDir) else {
                throw LassoError.noCaptures(captureDir)
            }
            let captureFiles = try fm.contentsOfDirectory(atPath: captureDir)
                .filter { $0.hasSuffix(".png") }
                .sorted()

            guard !captureFiles.isEmpty else {
                throw LassoError.noCaptures(captureDir)
            }

            if !options.json {
                print("Comparing \(captureFiles.count) screen(s) against baselines...")
            }

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
                            diffData: diffData
                        ))
                    } catch {
                        allPassed = false
                        screenUploads.append(RunScreenUpload(
                            name: screenName,
                            status: "error",
                            pixelThreshold: diffConfig.threshold,
                            perceptualThreshold: diffConfig.perceptualThreshold,
                            message: "Error: \(error.localizedDescription)",
                            captureData: captureData
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
                        captureData: captureData
                    ))
                }
            }

            // 3. Upload run results
            let duration = Date().timeIntervalSince(start)
            let upload = RunUpload(
                branch: branch,
                commitSHA: commitSHA?.trimmingCharacters(in: .whitespacesAndNewlines),
                trigger: trigger,
                duration: duration,
                screens: screenUploads
            )

            if !options.json {
                print("Uploading results...")
            }

            let runResponse = try await client.createRun(project, upload)

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
                commitSha: commitSHA?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        }
    }
}
