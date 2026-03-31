# View Hierarchy Dump Command

The `grantiva runner dump-hierarchy` command allows agents and developers to inspect the UI element tree of a running iOS app for automation and testing purposes.

## Prerequisites

The command requires the GrantivaDriver server to be running. This server is started automatically when running XCUITest tests with the GrantivaDriver test target.

## Usage

```bash
# Basic usage (tree format)
grantiva runner dump-hierarchy

# JSON format (for programmatic use)
grantiva runner dump-hierarchy --format json

# XML format (debugDescription)
grantiva runner dump-hierarchy --format xml

# Custom port
grantiva runner dump-hierarchy --port 8080
```

## Output Formats

### Tree Format (default)
Human-readable indented tree showing:
- Element type (Button, TextField, etc.)
- Label text
- Accessibility identifier
- Enabled/disabled state

Example:
```
[Application]
  [Window]
    [NavigationBar] label="Settings"
      [Button] label="Back"
      [StaticText] label="Settings"
    [ScrollView]
      [Table]
        [TableRow] label="Account"
        [TableRow] label="Privacy"
```

### JSON Format
Raw JSON with full element details including:
- `role`: Element type
- `label`: Accessibility label
- `value`: Current value
- `identifier`: Accessibility identifier
- `frame`: Position and size {x, y, width, height}
- `enabled`: Boolean enabled state
- `children`: Nested array of child elements

### XML Format
Apple's debugDescription format - a detailed XML-like representation of the full element hierarchy.

## Agent Integration

Agents can use this command to:

1. **Understand UI structure** before interacting with elements
2. **Identify correct accessibility identifiers** for tap/swipe actions
3. **Verify expected UI state** during automated testing
4. **Debug element visibility issues** when assertions fail

Example agent workflow:
```bash
# 1. Start the app with GrantivaDriver
# 2. Dump hierarchy to understand available elements
grantiva runner dump-hierarchy --format json > hierarchy.json

# 3. Parse JSON to find target element
# 4. Construct automation commands based on identifiers/labels
```

## Technical Details

The command connects to the GrantivaDriver HTTP server (default port 22088) which runs inside the XCUITest process. The server uses XCUIApplication snapshots to capture the current view hierarchy in real-time.

**Endpoints:**
- `GET /hierarchy` - JSON element tree
- `GET /source` - XML debugDescription

**Error Handling:**
- Connection failures indicate the GrantivaDriver server is not running
- 404 errors suggest the endpoint is not available (check GrantivaDriver version)
- Timeout errors may occur if the app is unresponsive
