@preconcurrency import XCTest
import Foundation

/// Handles HTTP requests by interacting with XCUIApplication.
/// All methods are called on the main thread from DriverServer.
@MainActor
final class RequestHandler: @unchecked Sendable {
    private let app: XCUIApplication
    private let bundleId: String?

    init(bundleId: String? = nil) {
        if let bundleId {
            self.bundleId = bundleId
            self.app = XCUIApplication(bundleIdentifier: bundleId)
        } else {
            self.bundleId = nil
            self.app = XCUIApplication()
        }
    }

    // MARK: - Health

    func health() -> DriverServer.Response {
        .json("{\"status\":\"ok\",\"bundleId\":\"\(bundleId ?? "default")\"}")
    }

    // MARK: - View Hierarchy

    func hierarchy() -> DriverServer.Response {
        let snapshot: XCUIElementSnapshot
        do {
            snapshot = try app.snapshot()
        } catch {
            return .error("Failed to get snapshot: \(error.localizedDescription)", status: 500)
        }

        let json = serializeElement(snapshot)
        return .json(json)
    }

    func pageSource() -> DriverServer.Response {
        // Returns the debugDescription which is a full XML-like hierarchy
        let desc = app.debugDescription
        return .json("{\"source\":\(escapeJSON(desc))}")
    }

    // MARK: - Tap

    func tap(body: String?) -> DriverServer.Response {
        guard let body, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .error("Invalid JSON body")
        }

        if let label = json["label"] as? String {
            let element = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ OR title == %@ OR value == %@", label, label, label
            )).firstMatch

            if element.exists {
                element.tap()
                return .json("{\"action\":\"tap\",\"label\":\(escapeJSON(label)),\"success\":true}")
            } else {
                return .error("Element not found: \(label)", status: 404)
            }
        } else if let x = json["x"] as? Double, let y = json["y"] as? Double {
            let normalized = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: x, dy: y))
            normalized.tap()
            return .json("{\"action\":\"tap\",\"x\":\(x),\"y\":\(y),\"success\":true}")
        }

        return .error("Provide 'label' or 'x'+'y'")
    }

    // MARK: - Swipe

    func swipe(body: String?) -> DriverServer.Response {
        guard let body, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .error("Invalid JSON body")
        }

        if let direction = json["direction"] as? String {
            switch direction {
            case "up":    app.swipeUp()
            case "down":  app.swipeDown()
            case "left":  app.swipeLeft()
            case "right": app.swipeRight()
            default:
                return .error("Invalid direction: \(direction). Use: up, down, left, right")
            }
            return .json("{\"action\":\"swipe\",\"direction\":\"\(direction)\",\"success\":true}")
        } else if let sx = json["startX"] as? Double, let sy = json["startY"] as? Double,
                  let ex = json["endX"] as? Double, let ey = json["endY"] as? Double {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: sx, dy: sy))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: ex, dy: ey))
            start.press(forDuration: 0, thenDragTo: end)
            return .json("{\"action\":\"swipe\",\"success\":true}")
        }

        return .error("Provide 'direction' or start/end coordinates")
    }

    // MARK: - Type

    func typeText(body: String?) -> DriverServer.Response {
        guard let body, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            return .error("Provide 'text' in JSON body")
        }

        // Type into the currently focused element
        // Find the first text field that has keyboard focus, or just type keys
        let textFields = app.textFields.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex
        if let focused = textFields.first(where: { ($0.value(forKey: "hasKeyboardFocus") as? Bool) == true }) {
            focused.typeText(text)
        } else {
            // Fallback: tap the first text field and type
            if let first = textFields.first, first.exists {
                first.tap()
                first.typeText(text)
            } else {
                // Last resort: use XCUIElement.typeText on the app itself
                app.typeText(text)
            }
        }

        return .json("{\"action\":\"type\",\"text\":\(escapeJSON(text)),\"success\":true}")
    }

    // MARK: - Serialization

    private func serializeElement(_ element: XCUIElementSnapshot, depth: Int = 0) -> String {
        let maxDepth = 50
        guard depth < maxDepth else { return "{\"role\":\"truncated\",\"children\":[]}" }

        let role = element.elementType.debugDescription
        let label = element.label.isEmpty ? "null" : escapeJSON(element.label)
        let value: String
        if let v = element.value {
            value = escapeJSON(String(describing: v))
        } else {
            value = "null"
        }
        let frame = element.frame
        let enabled = element.isEnabled
        let identifier = element.identifier.isEmpty ? "null" : escapeJSON(element.identifier)

        let childrenJSON: String
        let kids = element.children
        if kids.isEmpty {
            childrenJSON = "[]"
        } else {
            let childStrings = kids.map { serializeElement($0, depth: depth + 1) }
            childrenJSON = "[\(childStrings.joined(separator: ","))]"
        }

        return """
        {"role":\(escapeJSON(role)),"label":\(label),"value":\(value),"identifier":\(identifier),"frame":{"x":\(frame.origin.x),"y":\(frame.origin.y),"width":\(frame.width),"height":\(frame.height)},"enabled":\(enabled),"children":\(childrenJSON)}
        """
    }

    private func escapeJSON(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - XCUIElement.ElementType description

extension XCUIElement.ElementType {
    var debugDescription: String {
        switch self {
        case .any: return "Any"
        case .other: return "Other"
        case .application: return "Application"
        case .group: return "Group"
        case .window: return "Window"
        case .sheet: return "Sheet"
        case .drawer: return "Drawer"
        case .alert: return "Alert"
        case .dialog: return "Dialog"
        case .button: return "Button"
        case .radioButton: return "RadioButton"
        case .radioGroup: return "RadioGroup"
        case .checkBox: return "CheckBox"
        case .disclosureTriangle: return "DisclosureTriangle"
        case .popUpButton: return "PopUpButton"
        case .comboBox: return "ComboBox"
        case .menuButton: return "MenuButton"
        case .toolbarButton: return "ToolbarButton"
        case .popover: return "Popover"
        case .keyboard: return "Keyboard"
        case .key: return "Key"
        case .navigationBar: return "NavigationBar"
        case .tabBar: return "TabBar"
        case .tabGroup: return "TabGroup"
        case .toolbar: return "Toolbar"
        case .statusBar: return "StatusBar"
        case .table: return "Table"
        case .tableRow: return "TableRow"
        case .tableColumn: return "TableColumn"
        case .outline: return "Outline"
        case .outlineRow: return "OutlineRow"
        case .browser: return "Browser"
        case .collectionView: return "CollectionView"
        case .slider: return "Slider"
        case .pageIndicator: return "PageIndicator"
        case .progressIndicator: return "ProgressIndicator"
        case .activityIndicator: return "ActivityIndicator"
        case .segmentedControl: return "SegmentedControl"
        case .picker: return "Picker"
        case .pickerWheel: return "PickerWheel"
        case .switch: return "Switch"
        case .toggle: return "Toggle"
        case .link: return "Link"
        case .image: return "Image"
        case .icon: return "Icon"
        case .searchField: return "SearchField"
        case .scrollView: return "ScrollView"
        case .scrollBar: return "ScrollBar"
        case .staticText: return "StaticText"
        case .textField: return "TextField"
        case .secureTextField: return "SecureTextField"
        case .datePicker: return "DatePicker"
        case .textView: return "TextView"
        case .menu: return "Menu"
        case .menuItem: return "MenuItem"
        case .menuBar: return "MenuBar"
        case .menuBarItem: return "MenuBarItem"
        case .map: return "Map"
        case .webView: return "WebView"
        case .incrementArrow: return "IncrementArrow"
        case .decrementArrow: return "DecrementArrow"
        case .timeline: return "Timeline"
        case .ratingIndicator: return "RatingIndicator"
        case .valueIndicator: return "ValueIndicator"
        case .splitGroup: return "SplitGroup"
        case .splitter: return "Splitter"
        case .relevanceIndicator: return "RelevanceIndicator"
        case .colorWell: return "ColorWell"
        case .helpTag: return "HelpTag"
        case .matte: return "Matte"
        case .dockItem: return "DockItem"
        case .ruler: return "Ruler"
        case .rulerMarker: return "RulerMarker"
        case .grid: return "Grid"
        case .levelIndicator: return "LevelIndicator"
        case .cell: return "Cell"
        case .layoutArea: return "LayoutArea"
        case .layoutItem: return "LayoutItem"
        case .handle: return "Handle"
        case .stepper: return "Stepper"
        case .tab: return "Tab"
        case .touchBar: return "TouchBar"
        case .statusItem: return "StatusItem"
        @unknown default: return "Unknown(\(self.rawValue))"
        }
    }
}
