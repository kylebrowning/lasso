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
            RunnerStartCommand.self,
            RunnerStopCommand.self,
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

// MARK: - Session File

/// Shared session state persisted to `.grantiva/session.json`.
struct RunnerSessionInfo: Codable {
    let pid: Int32
    let wdaPort: UInt16
    let bundleId: String
    let udid: String
    let startedAt: Date

    static let path = ".grantiva/session.json"

    func write() throws {
        let dir = (Self.path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.path))
    }

    static func load() throws -> RunnerSessionInfo {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(RunnerSessionInfo.self, from: data)
    }

    static func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Check if the session process is still alive.
    var isAlive: Bool {
        kill(pid, 0) == 0
    }
}

// MARK: - Start

@available(macOS 15, *)
struct RunnerStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the runner with WDA and keep it alive for interactive use."
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "App bundle identifier (reads from grantiva.yml if omitted)")
    var bundleId: String?

    @Option(name: .long, help: "Simulator name or UDID (reads from grantiva.yml if omitted)")
    var simulator: String?

    func run() async throws {
        // Check for existing session
        if let existing = try? RunnerSessionInfo.load(), existing.isAlive {
            if options.json {
                print(try JSONOutput.string([
                    "status": "already_running",
                    "port": "\(existing.wdaPort)",
                    "pid": "\(existing.pid)",
                    "bundle_id": existing.bundleId,
                ]))
            } else {
                print("Runner already running (pid \(existing.pid), WDA port \(existing.wdaPort))")
                print("Use 'grantiva runner stop' to stop it first.")
            }
            return
        }

        // Resolve config
        let config = try? GrantivaConfig.load()
        let resolvedBundleId = bundleId ?? config?.bundleId
        guard let resolvedBundleId else {
            throw GrantivaError.invalidArgument(
                "No bundle ID. Pass --bundle-id or set bundle_id in grantiva.yml."
            )
        }

        let simName = simulator ?? config?.simulator ?? "iPhone 16"
        let simManager = SimulatorManager.live
        let device = try await simManager.boot(nameOrUDID: simName)

        if !options.json {
            print("Starting runner...")
            print("  Bundle ID: \(resolvedBundleId)")
            print("  Simulator: \(device.name) (\(device.udid))")
        }

        // Ensure runner binary is available
        let runner = RunnerManager.live
        try await runner.ensureAvailable()
        let runnerBin = runner.runnerPath()
        let runnerDir = runner.runnerDir()

        // Create a flow that launches the app and waits a long time (1 hour)
        let flowYaml = """
        appId: \(resolvedBundleId)
        ---
        - launchApp
        - waitForAnimationToEnd:
            timeout: 3600000
        """
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grantiva-session")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let flowPath = tempDir.appendingPathComponent("session-flow.yaml").path
        try flowYaml.write(toFile: flowPath, atomically: true, encoding: .utf8)

        // Start the runner as a background process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runnerBin)
        process.arguments = [
            "--platform", "ios",
            "--device", device.udid,
            "--no-ansi",
            "--no-app-install",
            "test",
            "--wait-for-idle-timeout", "0",
            flowPath,
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: runnerDir)

        // Capture stdout to parse WDA port
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Monitor output for WDA port
        var wdaPort: UInt16?
        let deadline = Date().addingTimeInterval(60) // 60s timeout for WDA startup

        // Read output in a background task
        let outputTask = Task<UInt16?, Never> {
            let handle = stdoutPipe.fileHandleForReading
            var accumulated = ""

            while Date() < deadline {
                let available = handle.availableData
                guard !available.isEmpty else {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    continue
                }
                if let chunk = String(data: available, encoding: .utf8) {
                    accumulated += chunk

                    // Look for WDA port in output (e.g., "WebDriverAgent started on port 8430")
                    // The runner logs the port in various formats, try common patterns
                    let patterns = [
                        "port[: ]+([0-9]+)",
                        "localhost:([0-9]+)",
                        "WDA.*?([0-9]{4,5})",
                    ]
                    for pattern in patterns {
                        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                           let match = regex.firstMatch(in: accumulated, range: NSRange(accumulated.startIndex..., in: accumulated)),
                           let range = Range(match.range(at: 1), in: accumulated) {
                            let portStr = String(accumulated[range])
                            if let p = UInt16(portStr), p > 1024 {
                                return p
                            }
                        }
                    }

                    // Also check if launchApp completed (WDA is definitely up)
                    if accumulated.contains("launchApp") && accumulated.contains("✓") {
                        // WDA is up but we didn't catch the port — try common WDA port
                        // Try to connect to discover it
                        for candidatePort: UInt16 in [8430, 8100, 8200] {
                            let testUrl = URL(string: "http://localhost:\(candidatePort)/status")!
                            if let (_, resp) = try? await URLSession.shared.data(from: testUrl),
                               let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                                return candidatePort
                            }
                        }
                    }
                }
            }
            return nil
        }

        wdaPort = await outputTask.value

        guard let port = wdaPort else {
            process.terminate()
            RunnerSessionInfo.remove()
            throw GrantivaError.commandFailed("Timed out waiting for WDA to start", 1)
        }

        // Write session file
        let session = RunnerSessionInfo(
            pid: process.processIdentifier,
            wdaPort: port,
            bundleId: resolvedBundleId,
            udid: device.udid,
            startedAt: Date()
        )
        try session.write()

        if options.json {
            print(try JSONOutput.string([
                "status": "started",
                "port": "\(port)",
                "pid": "\(process.processIdentifier)",
                "bundle_id": resolvedBundleId,
                "udid": device.udid,
            ]))
        } else {
            print("Runner started")
            print("  WDA port: \(port)")
            print("  PID: \(process.processIdentifier)")
            print("  Session: \(RunnerSessionInfo.path)")
            print("")
            print("Use 'grantiva runner dump-hierarchy' to inspect the view hierarchy.")
            print("Use 'grantiva runner stop' to stop the session.")
        }
    }
}

// MARK: - Stop

@available(macOS 15, *)
struct RunnerStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running runner session."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        guard let session = try? RunnerSessionInfo.load() else {
            if options.json {
                print(try JSONOutput.string(["status": "not_running"]))
            } else {
                print("No active session found.")
            }
            return
        }

        if session.isAlive {
            kill(session.pid, SIGTERM)
            // Give it a moment to clean up
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // Force kill if still alive
            if kill(session.pid, 0) == 0 {
                kill(session.pid, SIGKILL)
            }
        }

        RunnerSessionInfo.remove()

        if options.json {
            print(try JSONOutput.string(["status": "stopped", "pid": "\(session.pid)"]))
        } else {
            print("Runner stopped (pid \(session.pid))")
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

    @Option(name: .shortAndLong, help: "WDA port (auto-detected from active session if omitted)")
    var port: UInt16?

    @Option(name: .shortAndLong, help: "Output format: tree, json, or xml (default: tree)")
    var format: String = "tree"

    func run() async throws {
        // Resolve port from session or flag
        let wdaPort: UInt16
        if let flagPort = port {
            wdaPort = flagPort
        } else if let session = try? RunnerSessionInfo.load(), session.isAlive {
            wdaPort = session.wdaPort
        } else {
            throw GrantivaError.invalidArgument(
                "No active runner session. Start one with 'grantiva runner start' or pass --port."
            )
        }

        // WDA uses the WebDriver protocol. The source endpoint returns the page hierarchy.
        // First, get the active session ID
        let statusUrl = URL(string: "http://localhost:\(wdaPort)/status")!
        let (statusData, statusResponse) = try await URLSession.shared.data(from: statusUrl)

        guard let statusHttp = statusResponse as? HTTPURLResponse, statusHttp.statusCode == 200 else {
            throw GrantivaError.commandFailed(
                "Cannot connect to WDA on port \(wdaPort). Is the runner started?", 1
            )
        }

        // Parse session ID from status
        var sessionId: String?
        if let statusJson = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
           let sid = statusJson["sessionId"] as? String {
            sessionId = sid
        }

        // Fetch the page source (XML format from WDA)
        let sourceUrlString: String
        if let sid = sessionId {
            sourceUrlString = "http://localhost:\(wdaPort)/session/\(sid)/source"
        } else {
            sourceUrlString = "http://localhost:\(wdaPort)/source"
        }

        let sourceUrl = URL(string: sourceUrlString)!
        let (sourceData, sourceResponse) = try await URLSession.shared.data(from: sourceUrl)

        guard let sourceHttp = sourceResponse as? HTTPURLResponse, sourceHttp.statusCode == 200 else {
            let msg = String(data: sourceData, encoding: .utf8) ?? "Unknown error"
            throw GrantivaError.commandFailed("Failed to get hierarchy: \(msg)", 1)
        }

        // WDA returns JSON with a "value" key containing the XML source
        let xmlSource: String
        if let json = try? JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
           let value = json["value"] as? String {
            xmlSource = value
        } else if let raw = String(data: sourceData, encoding: .utf8) {
            xmlSource = raw
        } else {
            throw GrantivaError.commandFailed("Empty hierarchy response", 1)
        }

        switch format.lowercased() {
        case "xml":
            print(xmlSource)

        case "json":
            // Parse XML to JSON
            let parser = HierarchyXMLParser(xml: xmlSource)
            let tree = parser.parse()
            let jsonData = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
            print(String(data: jsonData, encoding: .utf8) ?? "{}")

        case "tree":
            // Parse XML and pretty-print as tree
            let parser = HierarchyXMLParser(xml: xmlSource)
            let tree = parser.parse()
            printTree(element: tree, indent: 0)

        default:
            throw GrantivaError.invalidArgument("Invalid format '\(format)'. Use: tree, json, or xml")
        }
    }

    private func printTree(element: [String: Any], indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        let type = element["type"] as? String ?? "Unknown"
        let label = element["label"] as? String
        let identifier = element["identifier"] as? String
        let name = element["name"] as? String
        let value = element["value"] as? String
        let enabled = element["enabled"] as? Bool ?? true

        var desc = "\(prefix)[\(type)]"
        if let label = label, !label.isEmpty {
            desc += " label=\"\(label)\""
        }
        if let name = name, !name.isEmpty, name != label {
            desc += " name=\"\(name)\""
        }
        if let identifier = identifier, !identifier.isEmpty {
            desc += " id=\"\(identifier)\""
        }
        if let value = value, !value.isEmpty {
            desc += " value=\"\(value)\""
        }
        if !enabled {
            desc += " (disabled)"
        }

        print(desc)

        if let children = element["children"] as? [[String: Any]] {
            for child in children {
                printTree(element: child, indent: indent + 1)
            }
        }
    }
}

// MARK: - XML Parser for WDA Hierarchy

/// Parses the XML page source from WebDriverAgent into a dictionary tree.
class HierarchyXMLParser: NSObject, XMLParserDelegate {
    private let xml: String
    private var stack: [NSMutableDictionary] = []
    private var root: [String: Any] = [:]

    init(xml: String) {
        self.xml = xml
    }

    func parse() -> [String: Any] {
        guard let data = xml.data(using: .utf8) else { return [:] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let node = NSMutableDictionary()
        node["type"] = elementName

        // Map WDA XML attributes to our format
        if let label = attributes["label"], !label.isEmpty {
            node["label"] = label
        }
        if let name = attributes["name"], !name.isEmpty {
            node["name"] = name
        }
        if let identifier = attributes["identifier"], !identifier.isEmpty {
            // WDA uses "name" for accessibilityIdentifier in some versions
            node["identifier"] = identifier
        }
        if let value = attributes["value"], !value.isEmpty {
            node["value"] = value
        }
        if let enabled = attributes["enabled"] {
            node["enabled"] = enabled == "true"
        }
        if let visible = attributes["visible"] {
            node["visible"] = visible == "true"
        }
        if let x = attributes["x"], let y = attributes["y"],
           let w = attributes["width"], let h = attributes["height"] {
            node["frame"] = ["x": x, "y": y, "width": w, "height": h]
        }

        node["children"] = NSMutableArray()

        if let parent = stack.last {
            (parent["children"] as? NSMutableArray)?.add(node)
        }

        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if let finished = stack.popLast(), stack.isEmpty {
            root = finished as! [String: Any]
        }
    }
}
