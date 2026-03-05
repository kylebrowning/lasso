import Foundation

public enum LassoError: Error, LocalizedError, Sendable {
    case simulatorNotRunning
    case simulatorWindowNotFound
    case elementNotFound(String)
    case buildFailed(String)
    case testFailed(String)
    case invalidImage
    case notAuthenticated
    case configNotFound
    case commandFailed(String, Int32)
    case invalidArgument(String)
    case diffSizeMismatch(baseline: String, current: String)
    case noCaptures(String)
    case driverCacheStale
    case networkError(String, Int)
    case baselineNotFound(String)
    case appNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .simulatorNotRunning:
            return "No simulator is running. Run: lasso sim boot \"iPhone 16\""
        case .simulatorWindowNotFound:
            return "Simulator window not found. Is the Simulator app visible?"
        case .elementNotFound(let label):
            return "Element not found: \"\(label)\". Run lasso ui a11y to inspect the tree."
        case .buildFailed(let message):
            return "Build failed: \(message)"
        case .testFailed(let message):
            return "Tests failed: \(message)"
        case .invalidImage:
            return "Invalid or unreadable image file."
        case .notAuthenticated:
            return "Not authenticated. Run: lasso auth login"
        case .configNotFound:
            return "lasso.yml not found. Run: lasso init"
        case .commandFailed(let cmd, let code):
            return "\(cmd) exited with code \(code)"
        case .invalidArgument(let msg):
            return "Invalid argument: \(msg)"
        case .diffSizeMismatch(let baseline, let current):
            return "Image size mismatch: baseline is \(baseline), current is \(current)"
        case .noCaptures(let dir):
            return "No captures found in \(dir). Run: lasso diff capture"
        case .driverCacheStale:
            return "Driver cache is missing or stale. Run: lasso driver build"
        case .networkError(let message, let statusCode):
            return "Network error (\(statusCode)): \(message)"
        case .baselineNotFound(let screen):
            return "Baseline not found for screen \"\(screen)\""
        case .appNotFound(let path):
            return "App bundle not found at \"\(path)\". Verify the path exists or run a build first."
        }
    }
}
