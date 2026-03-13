import ArgumentParser
import Foundation
import GrantivaCore

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json = false
}

struct BuildOptions: ParsableArguments {
    @Option(name: .long, help: "Path to a pre-built .app bundle or .ipa archive. Skips the build step.")
    var appFile: String?

    @Flag(name: .long, help: "Skip building and installing — assume the app is already on the simulator.")
    var noBuild: Bool = false

    /// True when the xcodebuild step should be skipped.
    var shouldSkipBuild: Bool { noBuild || appFile != nil }

    /// True when the install/launch step should be skipped (app already on sim).
    var shouldSkipInstall: Bool { noBuild }

    /// Resolves the product path for the app binary.
    /// - When `--app-file` is set: resolves the binary (extracting IPA if needed), validates it.
    /// - When `--no-build` is set: returns nil (no binary to install).
    /// - Otherwise: returns nil (caller should build normally).
    func resolveAppBinary() throws -> ResolvedBinary? {
        guard let appFile else { return nil }
        return try AppBinaryResolver.resolve(appFile)
    }

    /// Derives a bundle ID from the app binary if one was provided.
    func deriveBundleId() -> String? {
        guard let appFile else { return nil }
        let absPath = (appFile as NSString).standardizingPath
        if absPath.hasSuffix(".app") {
            return AppBinaryResolver.bundleId(from: absPath)
        }
        // For IPA, we'd need to extract first — bundle ID derivation
        // happens after resolve in the command flow.
        return nil
    }
}
