import ArgumentParser
import GrantivaCore
import Foundation

@available(macOS 15, *)
struct RunnerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "Manage the embedded UI automation runner.",
        subcommands: [
            RunnerInstallCommand.self,
            RunnerVersionCommand.self,
            DumpHierarchyCommand.self,
        ]
    )
}

// MARK: - Install

@available(macOS 15, *)
struct RunnerInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Extract or update the embedded runner binary."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        if !options.json {
            print("Extracting runner...")
        }

        let manager = RunnerManager.live
        try await manager.ensureAvailable()

        if options.json {
            print(try JSONOutput.string([
                "status": "installed",
                "path": manager.runnerPath(),
                "version": RunnerManager.runnerVersion,
            ]))
        } else {
            print("Runner installed at \(manager.runnerPath())")
            print("Version: \(RunnerManager.runnerVersion)")
        }
    }
}

// MARK: - Version

@available(macOS 15, *)
struct RunnerVersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show the embedded runner version."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        if options.json {
            print(try JSONOutput.string(["version": RunnerManager.runnerVersion]))
        } else {
            print("grantiva-runner \(RunnerManager.runnerVersion)")
        }
    }
}

// MARK: - Dump Hierarchy

@available(macOS 15, *)
struct DumpHierarchyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dump-hierarchy",
        abstract: "Dump the view hierarchy from a running app for agent inspection."
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "Server port (default: 22088)")
    var port: UInt16 = 22088

    @Option(name: .shortAndLong, help: "Output format: tree, json, or xml (default: tree)")
    var format: String = "tree"

    func run() async throws {
        // Connect to the GrantivaDriver server
        let urlString = "http://localhost:\(port)/hierarchy"
        guard let url = URL(string: urlString) else {
            throw GrantivaError.invalidArgument("Invalid URL: \(urlString)")
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrantivaError.commandFailed("Invalid response from driver server", 1)
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GrantivaError.commandFailed(
                "Driver server returned status \(httpResponse.statusCode): \(errorMessage)",
                Int32(httpResponse.statusCode)
            )
        }

        // Parse and format the response
        switch format.lowercased() {
        case "json":
            // Raw JSON output
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        case "xml":
            // Fetch the XML/source format instead
            let xmlUrl = URL(string: "http://localhost:\(port)/source")!
            let (xmlData, _) = try await URLSession.shared.data(from: xmlUrl)
            if let sourceData = try? JSONSerialization.jsonObject(with: xmlData) as? [String: Any],
               let source = sourceData["source"] as? String {
                print(source)
            } else {
                print(String(data: xmlData, encoding: .utf8) ?? "")
            }
        case "tree":
            // Pretty-print the hierarchy as a tree
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GrantivaError.commandFailed("Failed to parse hierarchy JSON", 1)
            }
            printTree(element: json, indent: 0)
        default:
            throw GrantivaError.invalidArgument("Invalid format '\(format)'. Use: tree, json, or xml")
        }
    }

    private func printTree(element: [String: Any], indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        let role = element["role"] as? String ?? "Unknown"
        let label = element["label"] as? String
        let identifier = element["identifier"] as? String
        let enabled = element["enabled"] as? Bool ?? true

        // Build the element description
        var desc = "\(prefix)[\(role)]"
        if let label = label, !label.isEmpty {
            desc += " label=\"\(label)\""
        }
        if let identifier = identifier, !identifier.isEmpty {
            desc += " id=\"\(identifier)\""
        }
        if !enabled {
            desc += " (disabled)"
        }

        print(desc)

        // Recurse into children
        if let children = element["children"] as? [[String: Any]] {
            for child in children {
                printTree(element: child, indent: indent + 1)
            }
        }
    }
}
