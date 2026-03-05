import ArgumentParser
import LassoCore

@available(macOS 15, *)
struct A11yCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "a11y",
        abstract: "Accessibility tree and violation checks."
    )

    @Flag(name: .long, help: "Only show violations")
    var check = false

    @OptionGroup var options: GlobalOptions

    var simulatorManager: SimulatorManager = .live

    func run() async throws {
        let udid = try await simulatorManager.bootedUDID()
        let ui = options.makeUIAutomation(udid: udid)

        if check {
            let violations = try await ui.accessibilityViolations()
            if options.json {
                print(try JSONOutput.string(violations))
            } else if violations.isEmpty {
                print("No accessibility violations found.")
            } else {
                print("\(violations.count) violation(s):")
                for v in violations {
                    print("  \(v.rule.rawValue): \(v.role) at (\(Int(v.frame.origin.x)),\(Int(v.frame.origin.y)) \(Int(v.frame.width))x\(Int(v.frame.height))) — \(v.suggestion)")
                }
            }
        } else {
            let tree = try await ui.hierarchy()
            if options.json {
                print(try JSONOutput.string(tree))
            } else {
                printTree(tree, indent: 0)
            }
        }
    }

    private func printTree(_ node: DriverNode, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        var desc = "\(prefix)\(node.role)"
        if let label = node.label, !label.isEmpty {
            desc += " \"\(label)\""
        }
        if let value = node.value, !value.isEmpty {
            desc += " = \"\(value)\""
        }
        if !node.enabled {
            desc += " [disabled]"
        }
        print(desc)
        for child in node.children {
            printTree(child, indent: indent + 1)
        }
    }
}
