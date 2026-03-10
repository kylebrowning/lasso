import CoreGraphics

public struct A11yViolation: Sendable, Codable {
    public let rule: Rule
    public let role: String
    public let frame: CGRect

    public enum Rule: String, Sendable, Codable {
        case missingLabel = "missing_label"
        case smallTapTarget = "small_tap_target"
    }

    public var suggestion: String {
        switch rule {
        case .missingLabel:
            return "Add an accessibilityLabel to this \(role)"
        case .smallTapTarget:
            return "Increase size to at least 44x44pt (currently \(Int(frame.width))x\(Int(frame.height)))"
        }
    }
}
