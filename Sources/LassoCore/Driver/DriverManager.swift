import Foundation

// MARK: - DriverConfig

public struct DriverConfig: Sendable {
    public let targetBundleId: String?
    public let simulatorName: String
    public let port: UInt16

    public init(
        targetBundleId: String? = nil,
        simulatorName: String,
        port: UInt16 = 22088
    ) {
        self.targetBundleId = targetBundleId
        self.simulatorName = simulatorName
        self.port = port
    }
}

// MARK: - DriverManager

public struct DriverManager: Sendable {
    public var start: @Sendable (DriverConfig) async throws -> Void
    public var stop: @Sendable () async throws -> Void
    public var isRunning: @Sendable () async -> Bool

    public init(
        start: @escaping @Sendable (DriverConfig) async throws -> Void,
        stop: @escaping @Sendable () async throws -> Void,
        isRunning: @escaping @Sendable () async -> Bool
    ) {
        self.start = start
        self.stop = stop
        self.isRunning = isRunning
    }
}

// MARK: - Convenience Init

extension DriverManager {
    public init(cache: DriverCache = .live) {
        let state = DriverProcessState()

        self.init(
            start: { config in
                // Ensure driver is cached and valid
                if !(await cache.isValid()) {
                    try await cache.buildAndCache(config.simulatorName)
                }

                let destination = "platform=iOS Simulator,name=\(config.simulatorName)"

                // Copy cached .xctestrun to a temp file in the same Products directory
                // so that __TESTROOT__ still resolves correctly to the sibling Debug-iphonesimulator/
                let cachedPath = cache.xctestrunPath()
                guard FileManager.default.fileExists(atPath: cachedPath) else {
                    throw LassoError.driverCacheStale
                }

                let cachedDir = URL(fileURLWithPath: cachedPath).deletingLastPathComponent().path
                let tempXctestrun = "\(cachedDir)/LassoDriver_run.xctestrun"
                let fm = FileManager.default
                if fm.fileExists(atPath: tempXctestrun) {
                    try fm.removeItem(atPath: tempXctestrun)
                }
                try fm.copyItem(atPath: cachedPath, toPath: tempXctestrun)

                // Inject environment variables into the temp xctestrun plist
                let envKeyPath = "TestConfigurations.0.TestTargets.0.EnvironmentVariables"
                var plutilCmds = [
                    "plutil -replace '\(envKeyPath).LASSO_DRIVER_PORT' -string '\(config.port)' '\(tempXctestrun)'"
                ]
                if let bundleId = config.targetBundleId {
                    plutilCmds.append(
                        "plutil -replace '\(envKeyPath).LASSO_TARGET_BUNDLE_ID' -string '\(bundleId)' '\(tempXctestrun)'"
                    )
                }
                for cmd in plutilCmds {
                    _ = try await shell(cmd)
                }

                // Launch xcodebuild test-without-building using the temp xctestrun
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                process.arguments = [
                    "test-without-building",
                    "-xctestrun", tempXctestrun,
                    "-destination", destination,
                    "-only-testing", "LassoDriverUITests/DriverTest/testStartDriver",
                ]

                // Capture stderr to a temp file for diagnostics if the driver fails to start
                process.standardOutput = FileHandle.nullDevice
                let stderrPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lasso_driver_stderr_\(ProcessInfo.processInfo.processIdentifier).log")
                FileManager.default.createFile(atPath: stderrPath.path, contents: nil)
                let stderrHandle = FileHandle(forWritingAtPath: stderrPath.path)
                process.standardError = stderrHandle ?? FileHandle.nullDevice

                try process.run()
                await state.setProcess(process)

                // Wait for the driver to become healthy
                let client = DriverClient.live(port: config.port)
                let maxAttempts = 90
                let retryDelay: UInt64 = 1_000_000_000 // 1 second

                for attempt in 1...maxAttempts {
                    // Check that the xcodebuild process is still alive
                    guard process.isRunning else {
                        stderrHandle?.closeFile()
                        let stderrOutput = (try? String(contentsOf: stderrPath, encoding: .utf8))
                            .map { $0.suffix(2000) }.map(String.init) ?? ""
                        try? FileManager.default.removeItem(at: stderrPath)
                        await state.clearProcess()
                        throw LassoError.commandFailed(
                            "xcodebuild test process exited (status \(process.terminationStatus)) before driver became healthy. stderr:\n\(stderrOutput)",
                            process.terminationStatus
                        )
                    }

                    do {
                        _ = try await client.health()
                        stderrHandle?.closeFile()
                        try? FileManager.default.removeItem(at: stderrPath)
                        return // Driver is ready
                    } catch {
                        if attempt == maxAttempts {
                            stderrHandle?.closeFile()
                            let stderrOutput = (try? String(contentsOf: stderrPath, encoding: .utf8))
                                .map { $0.suffix(2000) }.map(String.init) ?? ""
                            try? FileManager.default.removeItem(at: stderrPath)
                            process.terminate()
                            await state.clearProcess()
                            throw LassoError.commandFailed(
                                "Driver did not become healthy after \(maxAttempts) seconds. stderr:\n\(stderrOutput)",
                                1
                            )
                        }
                        try await Task.sleep(nanoseconds: retryDelay)
                    }
                }
            },
            stop: {
                guard let process = await state.process else { return }
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                await state.clearProcess()
            },
            isRunning: {
                guard let process = await state.process else { return false }
                return process.isRunning
            }
        )
    }
}

// MARK: - Failing Implementation

extension DriverManager {
    public static let failing = DriverManager(
        start: { _ in throw LassoError.commandFailed("DriverManager.failing: start", 1) },
        stop: { throw LassoError.commandFailed("DriverManager.failing: stop", 1) },
        isRunning: { false }
    )
}

// MARK: - Internal Process State

/// Actor-isolated mutable state for the background xcodebuild process.
private actor DriverProcessState {
    var process: Process?

    func setProcess(_ p: Process) {
        process = p
    }

    func clearProcess() {
        process = nil
    }
}
