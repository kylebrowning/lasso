# Lasso

Visual regression CI for iOS. Screenshot diffs on every pull request, automatically.

Lasso captures screenshots of your app's screens, diffs them against approved baselines, and posts the results as GitHub Check Runs. Catch visual regressions before they ship.

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

# Generate config
lasso init

# Build the XCUITest driver (once per Xcode version)
lasso driver build

# Authenticate with Lasso Range
lasso auth login

# Run the full CI pipeline
lasso ci run
```

## How It Works

1. **Boot** — boots the configured simulator
2. **Build** — builds the app with `xcodebuild`
3. **Launch** — installs and launches the app
4. **Navigate** — taps and swipes to each screen defined in `lasso.yml`
5. **Capture** — screenshots each screen via the XCUITest driver
6. **Diff** — compares against baselines (pixel + CIE76 perceptual color distance)
7. **Upload** — sends results to [Lasso Range](https://lasso.build)
8. **Check Run** — posts a GitHub Check Run with before/after diffs

All UI automation runs through a built-in XCUITest driver. No Accessibility permission needed. Works headless on CI out of the box.

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
```

### Screens

Each screen has a `name` and a `path`. The path describes how to navigate there:

- `launch` — screenshot immediately after app launch
- `- tap: "Label"` — tap a button or element by accessibility label
- `- swipe: up` — swipe in a direction
- `- wait: 2` — wait N seconds

Lasso navigates to each screen in order, captures a screenshot, then moves to the next.

## CI Integration

Add to your GitHub Actions workflow:

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
      - name: Run visual regression
        env:
          LASSO_API_KEY: ${{ secrets.LASSO_API_KEY }}
        run: lasso ci run
```

If your app is already built by a previous step:

```yaml
      - run: lasso ci run --skip-build
      # Or point to a pre-built .app
      - run: lasso ci run --app-path ./build/MyApp.app
```

Results upload to the [Lasso Range](https://lasso.build) dashboard and post as GitHub Check Runs on your PRs.

## Commands

```
lasso ci run             Run full CI pipeline (build → capture → diff → upload)
lasso diff capture       Capture screenshots for all configured screens
lasso diff compare       Diff captures against baselines
lasso diff approve       Promote captures to baselines
lasso auth login         Authenticate with Lasso Range
lasso auth status        Show current authentication
lasso auth logout        Remove stored credentials
lasso doctor             Check environment and dependencies
lasso driver build       Build and cache the XCUITest driver
lasso driver start       Start the driver server
lasso driver stop        Stop the driver server
lasso init               Generate lasso.yml
```

All commands support `--json` for structured output.

## Local Workflow

You can use Lasso locally without Lasso Range for free:

```bash
# Capture screenshots of all configured screens
lasso diff capture

# Compare against local baselines
lasso diff compare

# Approve current screenshots as the new baseline
lasso diff approve
```

Local baselines are stored in `.lasso/baselines/`. Connect to [Lasso Range](https://lasso.build) to store baselines remotely and enable CI across machines.

## License

MIT
