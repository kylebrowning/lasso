import Foundation

/// Resolves the path to the GrantivaDriver.xcodeproj, searching common locations.
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
            // From repo root: cli/Apps/GrantivaDriver/
            cwd.appendingPathComponent("Apps/GrantivaDriver/GrantivaDriver.xcodeproj"),
            // From sibling app dir: cli/Apps/SomeApp/ → ../GrantivaDriver/
            cwd.appendingPathComponent("../GrantivaDriver/GrantivaDriver.xcodeproj"),
            // From binary location (e.g. .build/debug/)
            binaryDir.appendingPathComponent("../../Apps/GrantivaDriver/GrantivaDriver.xcodeproj"),
            // Homebrew share directory (brew --prefix)/share/grantiva/
            binaryDir.appendingPathComponent("../share/grantiva/Apps/GrantivaDriver/GrantivaDriver.xcodeproj"),
        ]
        if let found = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            return found.path
        }
        throw GrantivaError.invalidArgument(
            "Cannot find GrantivaDriver.xcodeproj. Pass --project explicitly."
        )
    }
}
