import ArgumentParser
import Foundation
import GrantivaCore
import GrantivaAPI

struct DiffCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Visual regression testing — capture, compare, and approve screenshots.",
        subcommands: [CaptureCommand.self, CompareCommand.self, ApproveCommand.self]
    )

    // MARK: - Capture

    struct CaptureCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "capture",
            abstract: "Navigate to configured screens and capture screenshots."
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

        func run() async throws {
            let config = try? GrantivaConfig.load()

            // Resolve the app binary first (if provided) so we can derive bundle ID
            let resolvedBinary = try buildOptions.resolveAppBinary()
            defer { resolvedBinary?.cleanup() }

            let appBundleId = resolvedBinary.flatMap { AppBinaryResolver.bundleId(from: $0.appPath) }

            let resolved = try await ResolvedProject.resolve(
                schemeFlag: scheme, simulatorFlag: simulator, bundleIdFlag: bundleId, config: config,
                skipBuild: buildOptions.shouldSkipBuild,
                appBundleId: appBundleId
            )

            guard !resolved.screens.isEmpty else {
                throw GrantivaError.invalidArgument("No screens configured in grantiva.yml")
            }

            let outputDir = ".grantiva/captures"
            let start = Date()

            var device: SimulatorDevice

            if !buildOptions.shouldSkipInstall {
                // Full lifecycle: boot → build → install → launch → capture
                // OR: boot → install pre-built → launch → capture
                device = try await simulatorManager.boot(nameOrUDID: resolved.simulator)
                let destination = "platform=iOS Simulator,id=\(device.udid)"

                var productPath: String?

                if let resolvedBinary {
                    // Pre-built binary provided via --app-file
                    if !options.json {
                        print("Using pre-built binary: \(URL(fileURLWithPath: resolvedBinary.appPath).lastPathComponent)")
                    }
                    productPath = resolvedBinary.appPath
                } else {
                    // Build from source
                    guard let buildScheme = resolved.scheme else {
                        throw GrantivaError.invalidArgument(
                            "No scheme specified. Pass --scheme, set it in grantiva.yml, or use --app-file to provide a pre-built binary."
                        )
                    }

                    if !options.json {
                        print("Building \(buildScheme)...")
                    }

                    let buildResult = try await XcodeBuildRunner().build(
                        scheme: buildScheme,
                        workspace: resolved.workspace,
                        project: resolved.project,
                        destination: destination,
                        buildSettings: resolved.buildSettings
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

                // Install and launch
                if let bid = resolved.bundleId {
                    if let productPath {
                        try await XcodeBuildRunner().install(
                            bundleId: bid, productPath: productPath, udid: device.udid
                        )
                    }
                    try await XcodeBuildRunner().launch(bundleId: bid, udid: device.udid)
                    try await Task.sleep(for: .seconds(2))
                }

                if !options.json {
                    print("Capturing \(resolved.screens.count) screen(s)...")
                }
            } else {
                // --no-build: just use the currently booted simulator
                device = try await simulatorManager.bootedDevice()
            }

            guard let bid = resolved.bundleId else {
                throw GrantivaError.invalidArgument("Bundle ID is required for screen capture")
            }

            if !options.json {
                print("Capturing \(resolved.screens.count) screen(s)...")
            }

            let captures = try await RunnerSession.run(
                screens: resolved.screens,
                bundleId: bid,
                udid: device.udid,
                outputDir: outputDir
            )

            // Print step-by-step results
            if !options.json {
                for capture in captures {
                    print("\n  \(capture.screenName)")
                    for step in capture.steps {
                        let icon = step.status == .passed ? "\u{2713}" : "\u{2717}"
                        print("    \(icon) \(step.action)")
                        if let msg = step.message {
                            print("      \(msg)")
                        }
                    }
                }
                print("")
            }

            let result = CaptureResult(
                screens: captures,
                directory: outputDir,
                duration: Date().timeIntervalSince(start)
            )

            if options.json {
                print(try JSONOutput.string(result))
            } else {
                print(TableFormatter().formatCapture(result))
            }
        }
    }

    // MARK: - Compare

    struct CompareCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compare",
            abstract: "Diff current captures against baselines."
        )

        @OptionGroup var options: GlobalOptions
        @OptionGroup var buildOptions: BuildOptions

        @Option(name: .long, help: "Scheme to build")
        var scheme: String?

        @Option(name: .long, help: "Simulator name")
        var simulator: String?

        @Option(name: .long, help: "Bundle identifier")
        var bundleId: String?

        @Flag(name: .long, help: "Capture screenshots before comparing (runs full lifecycle)")
        var capture = false

        var simulatorManager: SimulatorManager = .live
        var imageDiffer: ImageDiffer = .live

        func run() async throws {
            let config = try? GrantivaConfig.load()
            let captureDir = ".grantiva/captures"
            let diffDir = ".grantiva/captures/diffs"
            let start = Date()

            // Optionally capture first (with full lifecycle)
            if capture {
                let resolvedBinary = try buildOptions.resolveAppBinary()
                defer { resolvedBinary?.cleanup() }

                let appBundleId = resolvedBinary.flatMap { AppBinaryResolver.bundleId(from: $0.appPath) }

                let resolved = try await ResolvedProject.resolve(
                    schemeFlag: scheme, simulatorFlag: simulator, bundleIdFlag: bundleId, config: config,
                    skipBuild: buildOptions.shouldSkipBuild,
                    appBundleId: appBundleId
                )

                guard !resolved.screens.isEmpty else {
                    throw GrantivaError.invalidArgument("No screens configured in grantiva.yml")
                }

                let device = try await simulatorManager.boot(nameOrUDID: resolved.simulator)

                if !buildOptions.shouldSkipInstall {
                    let destination = "platform=iOS Simulator,id=\(device.udid)"
                    var productPath: String?

                    if let resolvedBinary {
                        if !options.json {
                            print("Using pre-built binary: \(URL(fileURLWithPath: resolvedBinary.appPath).lastPathComponent)")
                        }
                        productPath = resolvedBinary.appPath
                    } else {
                        guard let buildScheme = resolved.scheme else {
                            throw GrantivaError.invalidArgument(
                                "No scheme specified. Pass --scheme, set it in grantiva.yml, or use --app-file to provide a pre-built binary."
                            )
                        }

                        if !options.json {
                            print("Building \(buildScheme)...")
                        }

                        let buildResult = try await XcodeBuildRunner().build(
                            scheme: buildScheme,
                            workspace: resolved.workspace,
                            project: resolved.project,
                            destination: destination,
                            buildSettings: resolved.buildSettings
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
                }

                guard let bid = resolved.bundleId else {
                    throw GrantivaError.invalidArgument("Bundle ID is required for screen capture")
                }

                if !options.json {
                    print("Capturing \(resolved.screens.count) screen(s)...")
                }

                let captures = try await RunnerSession.run(
                    screens: resolved.screens,
                    bundleId: bid,
                    udid: device.udid,
                    outputDir: captureDir
                )

                // Print step-by-step results
                if !options.json {
                    for capture in captures {
                        print("\n  \(capture.screenName)")
                        for step in capture.steps {
                            let icon = step.status == .passed ? "\u{2713}" : "\u{2717}"
                            print("    \(icon) \(step.action)")
                            if let msg = step.message {
                                print("      \(msg)")
                            }
                        }
                    }
                    print("")
                }
            }

            let diffConfig = config?.diff ?? .init()
            let fm = FileManager.default
            let store = try await DiffCommand.resolveBaselineStore()
            let differ = imageDiffer

            // Create diffs directory
            if !fm.fileExists(atPath: diffDir) {
                try fm.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
            }

            // Find capture files
            guard fm.fileExists(atPath: captureDir) else {
                throw GrantivaError.noCaptures(captureDir)
            }
            let captureFiles = try fm.contentsOfDirectory(atPath: captureDir)
                .filter { $0.hasSuffix(".png") }
                .sorted()

            guard !captureFiles.isEmpty else {
                throw GrantivaError.noCaptures(captureDir)
            }

            var screenDiffs: [ScreenDiff] = []
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

                        var diffImagePath: String? = nil
                        if !passed {
                            allPassed = false
                            let path = "\(diffDir)/\(screenName)_diff.png"
                            try output.diffImageData.write(to: URL(fileURLWithPath: path))
                            diffImagePath = path
                        }

                        let message = passed
                            ? "Passed"
                            : "Failed: pixel=\(String(format: "%.2f%%", output.pixelDiffPercent * 100)) perceptual=\(String(format: "%.1f", output.perceptualDistance))"

                        screenDiffs.append(ScreenDiff(
                            screenName: screenName,
                            status: passed ? .passed : .failed,
                            pixelDiffPercent: output.pixelDiffPercent,
                            perceptualDistance: output.perceptualDistance,
                            pixelThreshold: diffConfig.threshold,
                            perceptualThreshold: diffConfig.perceptualThreshold,
                            baselinePath: "\(store.baselineDirectory())/\(screenName).png",
                            capturePath: capturePath,
                            diffImagePath: diffImagePath,
                            message: message
                        ))
                    } catch {
                        allPassed = false
                        screenDiffs.append(ScreenDiff(
                            screenName: screenName,
                            status: .error,
                            pixelThreshold: diffConfig.threshold,
                            perceptualThreshold: diffConfig.perceptualThreshold,
                            capturePath: capturePath,
                            message: "Error: \(error.localizedDescription)"
                        ))
                    }
                } else {
                    // No baseline — new screen
                    screenDiffs.append(ScreenDiff(
                        screenName: screenName,
                        status: .newScreen,
                        pixelThreshold: diffConfig.threshold,
                        perceptualThreshold: diffConfig.perceptualThreshold,
                        capturePath: capturePath,
                        message: "New screen — no baseline. Run: grantiva diff approve"
                    ))
                }
            }

            let result = CompareResult(
                screens: screenDiffs,
                passed: allPassed,
                duration: Date().timeIntervalSince(start)
            )

            if options.json {
                print(try JSONOutput.string(result))
            } else {
                print(TableFormatter().formatCompare(result))
            }

            if !allPassed {
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Approve

    struct ApproveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "approve",
            abstract: "Promote current captures to baselines."
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Screen names to approve (default: all)")
        var screenNames: [String] = []

        func run() async throws {
            let captureDir = ".grantiva/captures"
            let fm = FileManager.default
            let store = try await DiffCommand.resolveBaselineStore()

            guard fm.fileExists(atPath: captureDir) else {
                throw GrantivaError.noCaptures(captureDir)
            }

            let allCaptures = try fm.contentsOfDirectory(atPath: captureDir)
                .filter { $0.hasSuffix(".png") }
                .sorted()

            guard !allCaptures.isEmpty else {
                throw GrantivaError.noCaptures(captureDir)
            }

            let toApprove: [String]
            if screenNames.isEmpty {
                toApprove = allCaptures.map { String($0.dropLast(4)) }
            } else {
                toApprove = screenNames
            }

            var approved: [String] = []
            for screenName in toApprove {
                let capturePath = "\(captureDir)/\(screenName).png"
                guard fm.fileExists(atPath: capturePath) else {
                    throw GrantivaError.noCaptures("No capture found for \"\(screenName)\"")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: capturePath))
                _ = try await store.save(screenName, data)
                approved.append(screenName)
            }

            let result = ApproveResult(
                approvedScreens: approved,
                baselineDirectory: store.baselineDirectory()
            )

            if options.json {
                print(try JSONOutput.string(result))
            } else {
                print(TableFormatter().formatApprove(result))
            }
        }
    }

    // MARK: - Baseline Store Resolution

    /// Resolves the baseline store: remote (via RangeClient) if authenticated, local otherwise.
    static func resolveBaselineStore() async throws -> BaselineStore {
        if let credentials = AuthStore.resolveCredentials() {
            let client = RangeClient(apiKey: credentials.apiKey, baseURL: credentials.baseURL)
            let projectId = try await ProjectIdentifier.resolve()
            return client.asBaselineStore(project: projectId.projectSlug, branch: projectId.currentBranch, baseURL: credentials.baseURL)
        }
        return .local()
    }
}
