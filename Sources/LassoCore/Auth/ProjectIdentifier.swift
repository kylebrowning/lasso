import Foundation

// MARK: - ProjectIdentifier

public struct ProjectIdentifier: Sendable {
    public var projectSlug: @Sendable () async throws -> String
    public var currentBranch: @Sendable () async throws -> String

    public init(
        projectSlug: @escaping @Sendable () async throws -> String,
        currentBranch: @escaping @Sendable () async throws -> String
    ) {
        self.projectSlug = projectSlug
        self.currentBranch = currentBranch
    }
}

// MARK: - Live

extension ProjectIdentifier {
    public static let live = ProjectIdentifier(
        projectSlug: {
            let remoteURL = try await shell("git remote get-url origin")
            return parseSlug(from: remoteURL)
        },
        currentBranch: {
            try await shell("git rev-parse --abbrev-ref HEAD")
        }
    )

    /// Parses "owner/repo" from a git remote URL.
    /// Handles:
    /// - https://github.com/owner/repo.git
    /// - https://github.com/owner/repo
    /// - git@github.com:owner/repo.git
    /// - git@github.com:owner/repo
    static func parseSlug(from remoteURL: String) -> String {
        var url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip .git suffix
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }

        // SSH format: git@github.com:owner/repo
        if url.contains("@") && url.contains(":") {
            if let colonIndex = url.lastIndex(of: ":") {
                return String(url[url.index(after: colonIndex)...])
            }
        }

        // HTTPS format: https://github.com/owner/repo
        if let urlObj = URL(string: url) {
            let components = urlObj.pathComponents.filter { $0 != "/" }
            if components.count >= 2 {
                return "\(components[components.count - 2])/\(components[components.count - 1])"
            }
        }

        return url
    }
}

// MARK: - Failing

extension ProjectIdentifier {
    public static let failing = ProjectIdentifier(
        projectSlug: { throw LassoError.commandFailed("ProjectIdentifier.failing: projectSlug", 1) },
        currentBranch: { throw LassoError.commandFailed("ProjectIdentifier.failing: currentBranch", 1) }
    )
}
