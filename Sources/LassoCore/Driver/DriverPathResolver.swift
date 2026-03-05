import Foundation

/// Resolves the path to the LassoDriver.xcodeproj, searching common locations.
public struct DriverPathResolver: Sendable {
    public var resolve: @Sendable () throws -> String

    public init(resolve: @escaping @Sendable () throws -> String) {
        self.resolve = resolve
    }
}

extension DriverPathResolver {
    public static let live = DriverPathResolver {
        let fm = FileManager.default
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let binaryDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent()
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let candidates = [
            // From repo root: lasso/Apps/LassoDriver/
            cwd.appendingPathComponent("Apps/LassoDriver/LassoDriver.xcodeproj"),
            // From sibling app dir: lasso/Apps/SomeApp/ → ../LassoDriver/
            cwd.appendingPathComponent("../LassoDriver/LassoDriver.xcodeproj"),
            // From binary location (e.g. .build/debug/)
            binaryDir.appendingPathComponent("../../Apps/LassoDriver/LassoDriver.xcodeproj"),
        ]
        if let found = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return found.path
        }
        throw LassoError.invalidArgument(
            "Cannot find LassoDriver.xcodeproj. Pass --project explicitly."
        )
    }
}
