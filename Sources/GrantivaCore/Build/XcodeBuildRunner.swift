import Foundation

public struct XcodeBuildRunner: Sendable {
    public init() {}

    public func build(
        scheme: String,
        workspace: String? = nil,
        project: String? = nil,
        destination: String = "platform=iOS Simulator,name=iPhone 16",
        buildSettings: [String] = []
    ) async throws -> BuildResult {
        let start = Date()
        var args = ["xcodebuild", "-scheme", scheme]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        args += ["-destination", "\(destination)", "build"]
        args += buildSettings

        let command = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")

        do {
            let output = try await shell(command)
            let duration = Date().timeIntervalSince(start)
            let warnings = output.components(separatedBy: "\n").filter { $0.contains("warning:") }
            let productPath = try? await resolveProductPath(
                scheme: scheme, workspace: workspace, project: project, destination: destination
            )
            return BuildResult(
                success: true, scheme: scheme, destination: destination,
                duration: duration, warnings: warnings, errors: [],
                productPath: productPath
            )
        } catch let error as GrantivaError {
            let duration = Date().timeIntervalSince(start)
            if case .commandFailed(let msg, _) = error {
                let errors = msg.components(separatedBy: "\n").filter { $0.contains("error:") }
                let warnings = msg.components(separatedBy: "\n").filter { $0.contains("warning:") }
                return BuildResult(
                    success: false, scheme: scheme, destination: destination,
                    duration: duration, warnings: warnings, errors: errors.isEmpty ? [msg] : errors,
                    productPath: nil
                )
            }
            throw error
        }
    }

    public func install(bundleId: String, productPath: String, udid: String) async throws {
        _ = try await shell("xcrun simctl install \(udid) \"\(productPath)\"")
    }

    public func launch(bundleId: String, udid: String) async throws {
        _ = try await shell("xcrun simctl launch \(udid) \(bundleId)")
    }

    public func terminate(bundleId: String, udid: String) async throws {
        _ = try await shell("xcrun simctl terminate \(udid) \(bundleId)")
    }

    public func uninstall(bundleId: String, udid: String) async throws {
        _ = try await shell("xcrun simctl uninstall \(udid) \(bundleId)")
    }

    public func test(
        scheme: String,
        workspace: String? = nil,
        project: String? = nil,
        destination: String = "platform=iOS Simulator,name=iPhone 16"
    ) async throws -> TestResult {
        let start = Date()
        var args = ["xcodebuild", "-scheme", scheme]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        args += ["-destination", "\(destination)", "test"]

        let command = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")

        do {
            let output = try await shell(command)
            let duration = Date().timeIntervalSince(start)
            let (passed, failed) = parseTestCounts(from: output)
            return TestResult(
                success: true, scheme: scheme, duration: duration,
                testsPassed: passed, testsFailed: failed, output: output
            )
        } catch let error as GrantivaError {
            let duration = Date().timeIntervalSince(start)
            if case .commandFailed(let msg, _) = error {
                let (passed, failed) = parseTestCounts(from: msg)
                return TestResult(
                    success: false, scheme: scheme, duration: duration,
                    testsPassed: passed, testsFailed: failed, output: msg
                )
            }
            throw error
        }
    }

    public func resolveProductPath(
        scheme: String, workspace: String?, project: String?, destination: String
    ) async throws -> String {
        var args = ["xcodebuild", "-scheme", scheme]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        args += ["-destination", "\(destination)", "-showBuildSettings"]
        let command = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        let output = try await shell(command)

        var builtProductsDir: String?
        var productName: String?
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
            }
            if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                productName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
            }
        }
        guard let dir = builtProductsDir, let name = productName else {
            throw GrantivaError.buildFailed("Could not resolve product path from build settings")
        }
        return "\(dir)/\(name)"
    }

    private func parseTestCounts(from output: String) -> (passed: Int, failed: Int) {
        var passed = 0
        var failed = 0
        for line in output.components(separatedBy: "\n") {
            if line.contains("Test Suite") && line.contains("passed") {
                passed += 1
            }
            if line.contains("Test Suite") && line.contains("failed") {
                failed += 1
            }
        }
        return (passed, failed)
    }
}

public struct TestResult: Sendable, Codable {
    public let success: Bool
    public let scheme: String
    public let duration: TimeInterval
    public let testsPassed: Int
    public let testsFailed: Int
    public let output: String

    public init(
        success: Bool,
        scheme: String,
        duration: TimeInterval,
        testsPassed: Int,
        testsFailed: Int,
        output: String
    ) {
        self.success = success
        self.scheme = scheme
        self.duration = duration
        self.testsPassed = testsPassed
        self.testsFailed = testsFailed
        self.output = output
    }
}
