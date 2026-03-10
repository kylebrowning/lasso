# Grantiva CLI

The command-line tool for [Grantiva](https://grantiva.io) — the all-in-one platform for iOS developers.

Currently features visual regression testing. Captures screenshots of your app's screens, diffs them against approved baselines, and posts the results as GitHub Check Runs. Catch visual regressions before they ship.

## Install

### Homebrew

```bash
brew install grantiva/tap/grantiva
```

### From source

```bash
git clone https://github.com/grantiva/cli.git
cd cli
swift build -c release
cp .build/release/grantiva /usr/local/bin/grantiva
```

**Requirements:** macOS 15+, Xcode 16+, Swift 6.1+

## Quick Start

```bash
# Check your environment
grantiva doctor

# Generate config
grantiva init

# Build the XCUITest driver (once per Xcode version)
grantiva driver build

# Authenticate with Grantiva
grantiva auth login

# Run the full CI pipeline
grantiva ci run
```

## How It Works

1. **Boot** — boots the configured simulator
2. **Build** — builds the app with `xcodebuild`
3. **Launch** — installs and launches the app
4. **Navigate** — taps and swipes to each screen defined in `grantiva.yml`
5. **Capture** — screenshots each screen via the XCUITest driver
6. **Diff** — compares against baselines (pixel + CIE76 perceptual color distance)
7. **Upload** — sends results to [Grantiva](https://grantiva.io)
8. **Check Run** — posts a GitHub Check Run with before/after diffs

All UI automation runs through a built-in XCUITest driver. No Accessibility permission needed. Works headless on CI out of the box.

## Configuration

Create a `grantiva.yml` in your project root (or run `grantiva init`):

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
```

### Screens

Each screen has a `name` and a `path`. The path describes how to navigate there:

- `launch` — screenshot immediately after app launch
- `- tap: "Label"` — tap a button or element by accessibility label
- `- swipe: up` — swipe in a direction
- `- wait: 2` — wait N seconds

Grantiva navigates to each screen in order, captures a screenshot, then moves to the next.

## CI Integration

Add to your GitHub Actions workflow:

```yaml
# .github/workflows/visual-regression.yml
name: Visual Regression
on: pull_request

jobs:
  visual-regression:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install Grantiva CLI
        run: brew install grantiva/tap/grantiva
      - name: Run visual regression
        env:
          GRANTIVA_API_KEY: ${{ secrets.GRANTIVA_API_KEY }}
        run: grantiva ci run
```

If your app is already built by a previous step:

```yaml
      - run: grantiva ci run --skip-build
      # Or point to a pre-built .app
      - run: grantiva ci run --app-path ./build/MyApp.app
```

Results upload to the [Grantiva](https://grantiva.io) dashboard and post as GitHub Check Runs on your PRs.

## Commands

```
grantiva ci run             Run full CI pipeline (build -> capture -> diff -> upload)
grantiva diff capture       Capture screenshots for all configured screens
grantiva diff compare       Diff captures against baselines
grantiva diff approve       Promote captures to baselines
grantiva auth login         Authenticate with Grantiva
grantiva auth status        Show current authentication
grantiva auth logout        Remove stored credentials
grantiva doctor             Check environment and dependencies
grantiva driver build       Build and cache the XCUITest driver
grantiva driver start       Start the driver server
grantiva driver stop        Stop the driver server
grantiva init               Generate grantiva.yml
```

All commands support `--json` for structured output.

## Local Workflow

You can use Grantiva locally without a Grantiva account:

```bash
# Capture screenshots of all configured screens
grantiva diff capture

# Compare against local baselines
grantiva diff compare

# Approve current screenshots as the new baseline
grantiva diff approve
```

Local baselines are stored in `.grantiva/baselines/`. Connect to [Grantiva](https://grantiva.io) to store baselines remotely and enable CI across machines.

## License

MIT
