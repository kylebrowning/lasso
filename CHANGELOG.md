# Changelog

## v1.2.0 — 2026-04-22

### Added
- `grantiva run --logs` streams simulator app logs (`xcrun simctl spawn log stream`) interleaved with flow output, prefixed with `[log]`. Default predicate is auto-derived from the resolved bundle ID.
- `--logs-predicate '<NSPredicate>'` overrides the default predicate for custom log filters.
- `--logs-level default|info|debug` passes through to `simctl`.
- Log streaming lifecycle is deferred — starts after simulator boot, stops on any exit path (success, failure, SIGINT, keep-alive release).

## v1.1.0 — 2026-04-22

### Added
- `grantiva run --keep-alive` holds the GrantivaAgent session open after flows complete. Writes a session file to `~/.grantiva/runner/sessions/<udid>.json` with port + session ID and blocks on Ctrl-C. The app stays frozen where the flow left it.
- `grantiva hierarchy` reads the keep-alive session file and dumps the live UI accessibility tree over HTTP (`/session/<id>/source`). Pure read, no relaunch. Supports `--format xml|json` and `--udid <UDID>` for multi-sim setups. Fails fast if no session is live rather than starting one behind the user's back.

### Notes
- Keep-alive + hierarchy together unblock agent-driven flows: run a flow, hold state, read hierarchy, synthesize a corrected selector, re-run.
- Runner rev bumped to `1.1.12-grantiva.3`.

## v1.0.0 — 2026-04-22

### Added
- **GrantivaAgent** — the WebDriverAgent embedded in the CLI now identifies as `GrantivaAgent` on the simulator home screen and in every runner log line. `CFBundleDisplayName` injected post-build into the test runner `.app`.
- Runner binary version now reports `1.1.12-grantiva.N` via `--version` so Grantiva-side rebuilds on the same upstream tag are distinguishable.
- `GRANTIVA_REV` env var in `scripts/build-runner.sh` lets us cut successive runner revisions without bumping upstream.

### Changed
- Runner log output — "WDA", "WebDriverAgent" replaced with "GrantivaAgent" in every user-visible string (`Starting…`, `Building…`, `already installed`, etc.). Internal identifiers (xctest scheme, bundle ID, derived data paths) unchanged so xcodebuild integration remains working.

## v0.9.1 — 2026-04-22

### Fixed
- `RunnerManager.runnerVersion` bumped to force re-extraction of the embedded runner tarball on upgrade. v0.9.0 shipped the new tarball but kept the old version string, so upgrading users silently kept running the old runner.

### Added
- CI guard that extracts the embedded tarball in `.github/workflows/ci.yml`, reads the binary's `--version`, and fails the build if it doesn't match `RunnerManager.runnerVersion`. Prevents future version-mismatch regressions.

## v0.9.0 — 2026-04-22

### Changed
- Embedded runner upgraded from `maestro-runner v1.0.9` to `v1.1.12`. 61 upstream commits inherited, including iOS WDA session lifecycle fixes, swipe coordinate fixes, `assertNotVisible` polling, `clearKeychain`, and `xcrun devicectl` install timeouts.

### Fixed
- `stopApp` and `killApp` are now idempotent — swallow `TerminateApp` errors when the app isn't running, matching upstream Maestro semantics. Flows starting with `- stopApp` no longer fail if the app hasn't been launched yet.

### Removed
- HTML, JUnit, and Allure report generation. Grantiva only consumes `report.json`; the other formats were cluttering user project directories with unused artifacts.
- Banner/footer output referencing upstream branding.
- Update check to `open.devicelab.dev`.

## v0.8.12 — 2026-04-22

### Fixed
- `grantiva run` no longer pre-launches the app before handing control to the flow. Flows own app lifecycle via `launchApp` / `clearState` / `stopApp`. The pre-launch was creating a process WDA had no handle on, causing any flow starting with `stopApp` to fail instantly with `Failed to stop app: <bundleId>`.

## v0.8.11 — 2026-04-22

### Fixed
- The built `.app` path is now forwarded to the runner as `--app-file` automatically. Flows using `clearState` (which uninstalls + reinstalls on iOS) no longer fail with `clearState on iOS requires --app-file to reinstall the app after uninstalling` when the user didn't pass `--app-file` on the CLI.

## v0.8.10 — 2026-04-22

### Fixed
- `xcodebuild -destination` now uses `id=<UDID>` instead of `name=<simulator name>`. On machines with multiple simulators sharing a name (or where the name-matched simulator's runtime doesn't satisfy the scheme's deployment target), xcodebuild no longer fails with `Unable to find a device matching the provided destination specifier` despite `simctl` having just booted the right simulator.
- Dropped the misleading hardcoded `name=iPhone 16` default argument on `XcodeBuildRunner.build` / `.test`.
