import Foundation

/// Resolves pre-built app binaries (.app bundles and .ipa archives) for simulator installation.
public struct AppBinaryResolver: Sendable {

    /// Resolves an app file path, handling IPA extraction if needed.
    /// Returns the path to a .app bundle ready for `simctl install`.
    public static func resolve(_ path: String) throws -> ResolvedBinary {
        let absPath = (path as NSString).standardizingPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: absPath) else {
            throw GrantivaError.appNotFound(absPath)
        }

        if absPath.hasSuffix(".ipa") {
            return try extractIPA(absPath)
        } else if absPath.hasSuffix(".app") {
            try validateSimulatorBuild(absPath)
            return ResolvedBinary(appPath: absPath, tempDir: nil)
        } else {
            let filename = URL(fileURLWithPath: absPath).lastPathComponent
            throw GrantivaError.invalidBinary(
                "Expected .app or .ipa file, got: \"\(filename)\""
            )
        }
    }

    /// Extract bundle ID from a .app bundle's Info.plist.
    public static func bundleId(from appPath: String) -> String? {
        guard let plist = readInfoPlist(appPath) else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    /// Validates that a .app bundle is built for the iOS Simulator (not a device build).
    public static func validateSimulatorBuild(_ appPath: String) throws {
        guard let plist = readInfoPlist(appPath) else {
            throw GrantivaError.invalidBinary(
                "Cannot read Info.plist in \(URL(fileURLWithPath: appPath).lastPathComponent). Is this a valid .app bundle?"
            )
        }

        if let platforms = plist["CFBundleSupportedPlatforms"] as? [String] {
            if !platforms.contains("iPhoneSimulator") {
                let platformStr = platforms.joined(separator: ", ")
                throw GrantivaError.invalidBinary(
                    "Binary is built for [\(platformStr)], not iPhoneSimulator. "
                    + "Rebuild with -destination 'generic/platform=iOS Simulator'."
                )
            }
        }
    }

    // MARK: - IPA Extraction

    /// Extract .app from an IPA (zip archive containing Payload/*.app).
    static func extractIPA(_ ipaPath: String) throws -> ResolvedBinary {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("grantiva-ipa-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", ipaPath, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? fm.removeItem(at: tempDir)
            let filename = URL(fileURLWithPath: ipaPath).lastPathComponent
            throw GrantivaError.ipaExtractionFailed(
                "Failed to unzip \(filename). Is this a valid IPA archive?"
            )
        }

        let payloadDir = tempDir.appendingPathComponent("Payload")
        guard fm.fileExists(atPath: payloadDir.path) else {
            try? fm.removeItem(at: tempDir)
            throw GrantivaError.ipaExtractionFailed(
                "No Payload/ directory found in IPA."
            )
        }

        let payloadContents = (try? fm.contentsOfDirectory(atPath: payloadDir.path)) ?? []
        guard let appName = payloadContents.first(where: { $0.hasSuffix(".app") }) else {
            try? fm.removeItem(at: tempDir)
            throw GrantivaError.ipaExtractionFailed(
                "No .app bundle found inside Payload/."
            )
        }

        let appPath = payloadDir.appendingPathComponent(appName).path
        try validateSimulatorBuild(appPath)

        return ResolvedBinary(appPath: appPath, tempDir: tempDir)
    }

    // MARK: - Private

    private static func readInfoPlist(_ appPath: String) -> [String: Any]? {
        let plistPath = "\(appPath)/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }
}

/// A resolved .app binary path, potentially backed by a temporary extraction directory.
public struct ResolvedBinary: Sendable {
    public let appPath: String

    /// If non-nil, this temp directory should be cleaned up when done.
    public let tempDir: URL?

    /// Remove the temp directory if one was created (e.g., from IPA extraction).
    public func cleanup() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
