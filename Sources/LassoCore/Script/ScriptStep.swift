import Foundation

public enum ScriptStep: Sendable, Codable, Equatable {
    case tap(label: String)
    case tapCoordinate(x: Double, y: Double)
    case swipe(direction: String)
    case type(text: String)
    case wait(seconds: Double)
    case screenshot(name: String?)
    case back
    case assertVisible(label: String)
    case assertNotVisible(label: String)
    case runFlow(path: String)

    enum CodingKeys: String, CodingKey {
        case action, label, x, y, direction, text, seconds, name, path
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)

        switch action {
        case "tap":
            if let label = try container.decodeIfPresent(String.self, forKey: .label) {
                self = .tap(label: label)
            } else {
                let x = try container.decode(Double.self, forKey: .x)
                let y = try container.decode(Double.self, forKey: .y)
                self = .tapCoordinate(x: x, y: y)
            }
        case "swipe":
            let direction = try container.decode(String.self, forKey: .direction)
            self = .swipe(direction: direction)
        case "type":
            let text = try container.decode(String.self, forKey: .text)
            self = .type(text: text)
        case "wait":
            let seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 1.0
            self = .wait(seconds: seconds)
        case "screenshot":
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            self = .screenshot(name: name)
        case "back":
            self = .back
        case "assert_visible":
            let label = try container.decode(String.self, forKey: .label)
            self = .assertVisible(label: label)
        case "assert_not_visible":
            let label = try container.decode(String.self, forKey: .label)
            self = .assertNotVisible(label: label)
        case "run_flow":
            let path = try container.decode(String.self, forKey: .path)
            self = .runFlow(path: path)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .action, in: container,
                debugDescription: "Unknown action: \(action). Valid: tap, swipe, type, wait, screenshot, back, assert_visible, assert_not_visible, run_flow"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tap(let label):
            try container.encode("tap", forKey: .action)
            try container.encode(label, forKey: .label)
        case .tapCoordinate(let x, let y):
            try container.encode("tap", forKey: .action)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .swipe(let direction):
            try container.encode("swipe", forKey: .action)
            try container.encode(direction, forKey: .direction)
        case .type(let text):
            try container.encode("type", forKey: .action)
            try container.encode(text, forKey: .text)
        case .wait(let seconds):
            try container.encode("wait", forKey: .action)
            try container.encode(seconds, forKey: .seconds)
        case .screenshot(let name):
            try container.encode("screenshot", forKey: .action)
            try container.encodeIfPresent(name, forKey: .name)
        case .back:
            try container.encode("back", forKey: .action)
        case .assertVisible(let label):
            try container.encode("assert_visible", forKey: .action)
            try container.encode(label, forKey: .label)
        case .assertNotVisible(let label):
            try container.encode("assert_not_visible", forKey: .action)
            try container.encode(label, forKey: .label)
        case .runFlow(let path):
            try container.encode("run_flow", forKey: .action)
            try container.encode(path, forKey: .path)
        }
    }

    public var description: String {
        switch self {
        case .tap(let label): return "tap \"\(label)\""
        case .tapCoordinate(let x, let y): return "tap (\(x), \(y))"
        case .swipe(let dir): return "swipe \(dir)"
        case .type(let text): return "type \"\(text)\""
        case .wait(let s): return "wait \(s)s"
        case .screenshot(let name): return "screenshot\(name.map { " \"\($0)\"" } ?? "")"
        case .back: return "back"
        case .assertVisible(let label): return "assert visible \"\(label)\""
        case .assertNotVisible(let label): return "assert not visible \"\(label)\""
        case .runFlow(let path): return "run flow \"\(path)\""
        }
    }
}
