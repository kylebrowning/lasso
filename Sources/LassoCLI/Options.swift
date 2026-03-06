import ArgumentParser
import Foundation
import LassoCore

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Option(name: .long, help: "Driver server port (default: 22088)")
    var driverPort: UInt16 = 22088
}

struct BuildOptions: ParsableArguments {
    @Flag(name: .long, help: "Skip building — use existing build artifacts from DerivedData.")
    var skipBuild: Bool = false

    @Option(name: .long, help: "Path to a pre-built .app bundle. Implies --skip-build.")
    var appPath: String?

    var shouldSkipBuild: Bool { skipBuild || appPath != nil }

    /// Resolves the product path when skipping build.
    /// Returns nil if build should proceed normally.
    func resolveProductPath(
        scheme: String, workspace: String?, project: String?, destination: String
    ) async throws -> String? {
        if let appPath {
            let abs = (appPath as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: abs) else {
                throw LassoError.appNotFound(abs)
            }
            return abs
        }
        if skipBuild {
            let path = try await XcodeBuildRunner().resolveProductPath(
                scheme: scheme, workspace: workspace, project: project, destination: destination
            )
            guard FileManager.default.fileExists(atPath: path) else {
                throw LassoError.appNotFound(path)
            }
            return path
        }
        return nil
    }
}
