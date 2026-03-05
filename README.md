# Lasso

An open-source Swift CLI that gives iOS development teams and their AI tools eyes, hands, and intelligence on the iOS Simulator.

Lasso wraps `xcodebuild`, `simctl`, and macOS accessibility APIs into a clean developer workflow — build, run, capture screenshots, diff against baselines, check accessibility, and run visual regression in CI. All from a single command-line tool.

## Install

### Mint (recommended)

```bash
brew install mint
mint install kylebrowning/lasso
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

# Generate config for your project
cd /path/to/your/ios/project
lasso init

# Build and run on simulator
lasso run --scheme MyApp

# Capture screenshots
lasso diff capture

# Compare against baselines
lasso diff compare

# Approve new baselines
lasso diff approve
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
lasso ui a11y            Dump the accessibility tree as JSON
lasso ui a11y --check    Check for accessibility violations

lasso diff capture       Capture screenshots for all configured screens
lasso diff compare       Diff captures against baselines
lasso diff approve       Promote captures to baselines

lasso auth login         Authenticate with Lasso Range
lasso auth status        Show current authentication
lasso auth logout        Remove stored credentials

lasso ci run             Run full CI pipeline (build → capture → diff → upload)

lasso mcp                Start MCP stdio server for AI agents
lasso driver build       Build and cache the XCUITest driver
```

Every command supports `--json` for structured output.

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
        run: |
          brew install mint
          mint install kylebrowning/lasso
      - name: Run visual diff
        env:
          LASSO_API_KEY: ${{ secrets.LASSO_API_KEY }}
        run: lasso ci run
```

Results upload to the Lasso Range dashboard and post as GitHub Check Runs on your PRs.

## MCP Server

Lasso exposes all capabilities as [MCP](https://modelcontextprotocol.io) tools for AI agents like Claude Code:

```bash
lasso mcp
```

Tools include `lasso_build`, `lasso_run`, `lasso_screenshot`, `lasso_tap`, `lasso_swipe_up`, `lasso_swipe_down`, `lasso_type`, `lasso_a11y_tree`, `lasso_a11y_check`, `lasso_sim_list`, `lasso_sim_boot`, `lasso_diff`.

## How It Works

- **UI automation** uses `AXUIElement` (accessibility API) for label-based taps and `CGEvent` for coordinate taps/swipes. No private frameworks.
- **Screenshots** use `xcrun simctl io screenshot`.
- **Text input** uses `xcrun simctl io type`.
- **Visual diffing** compares screenshots pixel-by-pixel with CIE76 perceptual color distance.
- **XCUITest driver** runs navigation steps through a cached driver app — built once, reused until Xcode updates.

## License

MIT
