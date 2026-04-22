import ArgumentParser
import Foundation
import GrantivaCore

/// Dumps the current UI hierarchy of a simulator via a running GrantivaAgent
/// session. Requires that `grantiva run --keep-alive` is actively holding the
/// session open in another shell, or on CI as a backgrounded process.
struct HierarchyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hierarchy",
        abstract: "Dump the UI hierarchy of a booted simulator without relaunching the app.",
        discussion: """
        Reads the session file written by `grantiva run --keep-alive` and issues a \
        read-only request to GrantivaAgent for the current page source. The target \
        app is never touched — no launch, no stopApp, no clearState.

        Typical agent workflow:

            # Terminal 1 (or backgrounded in CI):
            grantiva run --keep-alive --flow flows/onboarding.yaml

            # Terminal 2:
            grantiva hierarchy > state.xml

        If no keep-alive session is running, this command fails with a clear \
        message rather than trying to start one (which would relaunch the app \
        and destroy the state you wanted to inspect).
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Simulator UDID to target (default: newest keep-alive session)")
    var udid: String?

    @Option(name: .long, help: "Output format: xml or json")
    var format: OutputFormat = .xml

    enum OutputFormat: String, ExpressibleByArgument {
        case xml
        case json
    }

    func run() async throws {
        let session = try locateSession()

        let path = format == .json
            ? "/session/\(session.sessionId)/source?format=json"
            : "/session/\(session.sessionId)/source"

        guard let url = URL(string: "http://127.0.0.1:\(session.port)\(path)") else {
            throw GrantivaError.invalidArgument("Failed to build GrantivaAgent URL")
        }

        let request = URLRequest(url: url, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrantivaError.commandFailed("GrantivaAgent returned a non-HTTP response", 1)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GrantivaError.commandFailed(
                "GrantivaAgent /source failed (HTTP \(http.statusCode)):\n\(body.prefix(500))",
                Int32(http.statusCode)
            )
        }

        // WDA wraps /source in {"value": "<xml>"}. Unwrap for cleanliness.
        if format == .xml, let wrapped = unwrapWDASource(data) {
            print(wrapped)
        } else {
            FileHandle.standardOutput.write(data)
            print("")
        }
    }

    private func locateSession() throws -> KeepAliveSession {
        let dir = sessionsDir()
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else {
            throw GrantivaError.invalidArgument(
                "No keep-alive session found. Start one with `grantiva run --keep-alive` first."
            )
        }

        let jsonFiles = contents.filter { $0.hasSuffix(".json") }
        guard !jsonFiles.isEmpty else {
            throw GrantivaError.invalidArgument(
                "No keep-alive session found in \(dir). Start one with `grantiva run --keep-alive` first."
            )
        }

        if let udid {
            let path = "\(dir)/\(udid).json"
            guard fm.fileExists(atPath: path) else {
                throw GrantivaError.invalidArgument(
                    "No keep-alive session for udid \(udid). Available: \(jsonFiles.map { ($0 as NSString).deletingPathExtension }.joined(separator: ", "))"
                )
            }
            return try loadSession(path: path)
        }

        // Pick the most recently modified session file.
        let withDates: [(String, Date)] = jsonFiles.compactMap {
            let path = "\(dir)/\($0)"
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let date = attrs[.modificationDate] as? Date else { return nil }
            return (path, date)
        }
        guard let newest = withDates.max(by: { $0.1 < $1.1 }) else {
            throw GrantivaError.invalidArgument("Could not read any session file in \(dir)")
        }
        return try loadSession(path: newest.0)
    }

    private func loadSession(path: String) throws -> KeepAliveSession {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(KeepAliveSession.self, from: data)
    }

    private func sessionsDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.grantiva/runner/sessions"
    }

    /// WDA returns `{"value": "<?xml…>", "sessionId": "…"}`. Extract the XML.
    private func unwrapWDASource(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj["value"] as? String else {
            return nil
        }
        return value
    }
}

private struct KeepAliveSession: Decodable {
    let udid: String
    let port: Int
    let sessionId: String
    let appId: String?
}
