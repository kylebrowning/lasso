# Lasso

An open-source Swift CLI that gives iOS development teams and their AI tools eyes, hands, and intelligence on the iOS Simulator.

Lasso wraps `xcodebuild`, `simctl`, and a built-in XCUITest driver into a clean developer workflow — build, run, tap, swipe, capture screenshots, diff against baselines, check accessibility, and run visual regression in CI. All from a single command-line tool.

## Install

### Homebrew

```bash
brew install kylebrowning/lasso/lasso
```

### From source

```bash
git clone https://github.com/kylebrowning/lasso.git
cd lasso
swift build -c release
cp .build/release/lasso /usr/local/bin/lasso
```

**Requirements:** macOS 15+, Xcode 16+, Swift 6.1+

## Quick Start

```bash
# Check your environment
lasso doctor

# Boot a simulator
lasso sim boot "iPhone 16"

# Build and cache the UI driver (once per Xcode version)
lasso driver build

# Build and run your app
lasso run --scheme MyApp

# Start the driver, then automate
lasso driver start --bundle-id com.example.myapp
lasso ui a11y          # inspect the accessibility tree
lasso ui tap "Sign In" # tap a button
lasso ui screenshot    # capture the screen
```

## Commands

```
lasso build              Build the Xcode project
lasso run                Build + install + launch on simulator
lasso test               Run tests with structured output
lasso sim list           List available simulators
lasso sim boot           Boot a simulator by name or UDID
lasso doctor             Check environment and dependencies
lasso init               Generate lasso.yml config
lasso context            Dump project info for AI context

lasso ui tap             Tap by accessibility label or coordinates
lasso ui swipe           Swipe in a direction or between coordinates
lasso ui type            Type text into the focused field
lasso ui screenshot      Capture a simulator screenshot
lasso ui a11y            Dump the accessibility tree (pruned by default)
lasso ui a11y --full     Dump the full unfiltered tree
lasso ui a11y --check    Check for accessibility violations

lasso diff capture       Capture screenshots for all configured screens
lasso diff compare       Diff captures against baselines
lasso diff approve       Promote captures to baselines

lasso log                Stream simulator logs
lasso log --last 5m      Show recent logs
  --subsystem <id>       Filter by subsystem (e.g. com.example.myapp)
  --level <level>        Filter by level (default, info, debug, error, fault)

lasso script <file>      Run a YAML script of UI actions

lasso auth login         Authenticate with Lasso Range
lasso auth status        Show current authentication
lasso auth logout        Remove stored credentials

lasso ci run             Run full CI pipeline (build → capture → diff → upload)

lasso driver build       Build and cache the XCUITest driver
lasso driver start       Start the driver server
lasso driver stop        Stop the driver server

lasso mcp                Start MCP stdio server for AI agents
```

Every command supports `--json` for structured output.

## Scripts

Run a sequence of UI actions from a YAML file:

```yaml
# login-flow.yml
- action: tap
  label: "Sign In"
- action: wait
  seconds: 1
- action: tap
  label: "Email"
- action: type
  text: "user@example.com"
- action: tap
  label: "Password"
- action: type
  text: "hunter2"
- action: tap
  label: "Submit"
- action: wait
  seconds: 2
- action: screenshot
  name: logged-in
```

```bash
lasso script login-flow.yml
```

Available actions: `tap` (by label or x/y), `swipe` (up/down/left/right), `type`, `wait`, `screenshot`, `back`.

## Configuration

Create a `lasso.yml` in your project root (or run `lasso init`):

```yaml
scheme: MyApp
simulator: iPhone 16
bundle_id: com.example.myapp

screens:
  - name: Home
    path: launch
  - name: Settings
    path:
      - tap: "Profile"
      - tap: "Settings"

diff:
  threshold: 0.02
  perceptual_threshold: 5.0

a11y:
  fail_on_new_violations: true
  rules:
    - missing_label
    - small_tap_target
```

## CI Integration

Lasso runs visual regression checks on every pull request when connected to [Lasso Range](https://lasso.build).

```yaml
# .github/workflows/lasso.yml
name: Lasso Visual Regression
on: pull_request

jobs:
  lasso:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install Lasso
        run: brew install kylebrowning/lasso/lasso
      - name: Run visual diff
        env:
          LASSO_API_KEY: ${{ secrets.LASSO_API_KEY }}
        run: lasso ci run
```

If your app is already built by a previous CI step, skip the build:

```yaml
      - name: Run visual diff (skip build)
        env:
          LASSO_API_KEY: ${{ secrets.LASSO_API_KEY }}
        run: lasso ci run --skip-build

      # Or point to a specific .app from another job's artifacts
      - name: Run visual diff (pre-built app)
        env:
          LASSO_API_KEY: ${{ secrets.LASSO_API_KEY }}
        run: lasso ci run --app-path ./build/MyApp.app
```

Results upload to the Lasso Range dashboard and post as GitHub Check Runs on your PRs.

## MCP Server

Lasso exposes all capabilities as [MCP](https://modelcontextprotocol.io) tools for AI agents like Claude Code:

```bash
# Add to Claude Code
claude mcp add lasso -- lasso mcp
```

Tools: `lasso_build`, `lasso_run`, `lasso_screenshot`, `lasso_tap`, `lasso_swipe`, `lasso_type`, `lasso_a11y_tree`, `lasso_a11y_check`, `lasso_sim_list`, `lasso_sim_boot`, `lasso_logs`, `lasso_script`.

The `lasso_script` tool lets AI agents batch multiple actions in a single call instead of making individual tool calls with waits between them:

```json
{
  "steps": [
    {"action": "tap", "label": "Settings"},
    {"action": "wait", "seconds": 1},
    {"action": "swipe", "direction": "down"},
    {"action": "screenshot"}
  ]
}
```

## How It Works

- **UI automation** runs through a built-in XCUITest driver — no Accessibility permission needed, works on CI out of the box.
- **Screenshots** captured via the driver or `xcrun simctl io screenshot` as fallback.
- **Text input** uses the driver or `xcrun simctl io type`.
- **Visual diffing** compares screenshots pixel-by-pixel with CIE76 perceptual color distance.
- **XCUITest driver** is built once and cached at `~/.lasso/driver/`. Rebuilds automatically when Xcode updates.
- **No private frameworks.** No idb, no AXe, no vendored binaries.

## License

MIT
