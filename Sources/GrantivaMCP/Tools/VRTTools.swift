import Foundation
import GrantivaCore
import MCP

/// Visual Regression Testing tools: capture, compare, and approve screenshots.
/// These shell out to the grantiva CLI diff subcommands.
@available(macOS 15, *)
enum VRTTools {

    // MARK: - Tool Definitions

    static let definitions: [Tool] = [
        Tool(
            name: "grantiva_vrt_capture",
            description: "Capture screenshots for all configured screens. Equivalent to 'grantiva diff capture --no-build --json'. Assumes the app is already running on the simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screens": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional list of screen names to capture. If omitted, captures all configured screens."),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_vrt_compare",
            description: "Compare current captures against baselines. Equivalent to 'grantiva diff compare --json'. Returns diff results per screen with pixel and perceptual metrics.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_vrt_approve",
            description: "Promote current captures to baselines. Equivalent to 'grantiva diff approve [screens] --json'. Approves all screens if none specified.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screens": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Screen names to approve. If omitted, approves all."),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
    ]

    // MARK: - Handlers

    static func capture(arguments: [String: Value]) async throws -> CallTool.Result {
        let cmd = "grantiva diff capture --no-build --json"

        // We don't currently support per-screen filtering via the CLI,
        // but we include the parameter for future use
        if let screens = arguments["screens"]?.arrayValue {
            let names = screens.compactMap { $0.stringValue }
            if !names.isEmpty {
                // Reserved for future per-screen capture support
                _ = names
            }
        }

        do {
            let output = try await shell(cmd)
            return CallTool.Result(
                content: [.text(text: output, annotations: nil, _meta: nil)]
            )
        } catch let error as GrantivaError {
            if case .commandFailed(let msg, _) = error {
                return CallTool.Result(
                    content: [.text(text: "Capture failed:\n\(msg)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            throw error
        }
    }

    static func compare(arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let output = try await shell("grantiva diff compare --json")
            return CallTool.Result(
                content: [.text(text: output, annotations: nil, _meta: nil)]
            )
        } catch let error as GrantivaError {
            if case .commandFailed(let msg, _) = error {
                // Compare may exit non-zero on diffs found - that's expected
                return CallTool.Result(
                    content: [.text(text: msg, annotations: nil, _meta: nil)]
                )
            }
            throw error
        }
    }

    static func approve(arguments: [String: Value]) async throws -> CallTool.Result {
        var cmd = "grantiva diff approve --json"

        if let screens = arguments["screens"]?.arrayValue {
            let names = screens.compactMap { $0.stringValue }
            if !names.isEmpty {
                cmd += " " + names.joined(separator: " ")
            }
        }

        do {
            let output = try await shell(cmd)
            return CallTool.Result(
                content: [.text(text: output, annotations: nil, _meta: nil)]
            )
        } catch let error as GrantivaError {
            if case .commandFailed(let msg, _) = error {
                return CallTool.Result(
                    content: [.text(text: "Approve failed:\n\(msg)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            throw error
        }
    }
}
