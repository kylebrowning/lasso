import Foundation

public struct ProjectIdentifier: Sendable, Codable {
    public let projectSlug: String
    public let currentBranch: String

    public init(projectSlug: String, currentBranch: String) {
        self.projectSlug = projectSlug
        self.currentBranch = currentBranch
    }
}

// MARK: - Resolve

extension ProjectIdentifier {
    public static func resolve() async throws -> ProjectIdentifier {
        let remoteURL = try await shell("git remote get-url origin")
        let branch: String
        if let ciBranch = resolveBranch() {
            branch = ciBranch
        } else {
            branch = try await shell("git rev-parse --abbrev-ref HEAD")
        }
        return ProjectIdentifier(
            projectSlug: parseSlug(from: remoteURL),
            currentBranch: branch
        )
    }

    /// Resolves the branch name from CI environment variables.
    /// GitHub Actions checks out in detached HEAD, so git rev-parse returns "HEAD".
    static func resolveBranch() -> String? {
        let env = ProcessInfo.processInfo.environment
        // PR branch (GitHub Actions)
        if let head = env["GITHUB_HEAD_REF"], !head.isEmpty {
            return head
        }
        // Push branch (GitHub Actions)
        if let ref = env["GITHUB_REF_NAME"], !ref.isEmpty {
            return ref
        }
        return nil
    }

    /// Parses "owner/repo" from a git remote URL.
    static func parseSlug(from remoteURL: String) -> String {
        var url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

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
