# v2.0.0 — Swift-Native Runner

**Status:** Proposed
**Author:** Kyle
**Target cutover:** When the Swift implementation passes every flow in `grantiva-examples`

## Why

The Go runner (`grantiva-runner`, forked from `devicelab-dev/maestro-runner`) has served us well, but every grantiva-specific feature in v0.x → v1.x has gone through the same cycle:

1. Patch Go source in `scripts/grantiva-runner.patch`.
2. Rebuild runner binary (arm64 + amd64, ~25 MB each).
3. Rebuild WDA cache against the patched source.
4. Bump `GRANTIVA_REV` + `RunnerManager.runnerVersion`.
5. Commit ~45 MB of binary tarballs.
6. Ship via Homebrew.

This session alone went through that loop four times (v0.9.0 runner upgrade, v1.0.0 rebrand, v1.0.1 runner-version-mismatch fix, v1.1.0 keep-alive + hierarchy). Each round is 10–20 minutes of mechanical work and adds delta to a patch that has to be re-applied every time we rebase upstream.

A Swift-native runner embedded directly in the `grantiva` binary removes:
- The embedded 24 MB Go blob (and the Homebrew-formula hack to install a `libexec/grantiva_GrantivaCore.bundle` alongside it).
- The patch-rebuild-rebase cycle.
- The Go toolchain dependency on every contributor machine.
- An entire language and stack trace from the debugging surface.

The strategic payoff is faster iteration on agent-facing features — hierarchy dump, selector repair, AI-driven flow synthesis, "explain why this step failed" — all become 20-minute Swift edits instead of 2-hour runner patch cycles.

## Non-goals

- **Feature parity with Maestro / upstream maestro-runner.** We drop Android (UIAutomator2, DeviceLab), Appium, Flutter VM Service, cloud providers (Sauce, BrowserStack, etc.), HTML/JUnit/Allure reports, and the update checker. Re-add any of these only on validated customer demand.
- **Supporting existing Maestro flow features we don't use.** If a Maestro YAML keyword isn't in any `grantiva-examples` flow and no customer has asked for it, it's out of scope.
- **Linux support.** macOS only, because iOS simulators only run on macOS. If grantiva ever needs to run against remote device farms, that's a separate architecture.

## Scope (iOS-only, WDA-only, macOS-only)

### Must have (v2.0.0)

- **Flow YAML parsing** via [Yams](https://github.com/jpsim/Yams). Support every step currently used in `grantiva-examples`: `launchApp`, `stopApp`, `clearState` (only if we find we can't drop it), `tapOn`, `assertVisible`, `assertNotVisible`, `inputText`, `swipe`, `waitForAnimationToEnd`, `takeScreenshot`, `runFlow`.
- **WDA lifecycle**: build via `xcodebuild` (Process), port derivation from UDID, xctestrun plist injection (PropertyListSerialization), process supervision, cleanup on signal.
- **WDA HTTP client** via URLSession: session create/delete, tap, input, source, screenshot, element find/click, settings update.
- **Simulator management**: discover booted sims (`xcrun simctl list --json`), boot if needed, install/uninstall app, launch.
- **Screenshot + report.json** output (compatible with existing `.grantiva/captures/` downstream consumers).
- **Keep-alive mode** (already designed in v1.1.0 — port the concept).
- **Hierarchy dump** (Swift already does this in v1.1.0 — no porting needed).

### Should have (v2.0.x follow-ups)

- `grantiva repl` — interactive REPL that holds a WDA session and accepts step commands via stdin, for agent-driven flow authoring.
- `grantiva explain <failure>` — given a failed step + hierarchy snapshot, suggest selectors or diagnose the root cause.
- Screenshot diffing moved into Swift (currently in `GrantivaCore/Diff/` — already Swift, bonus).

### Won't have

- Android drivers (UIAutomator2, DeviceLab, Appium).
- Cloud providers.
- Flutter VM Service fallback.
- HTML / JUnit / Allure reports.
- Update checker.
- The upstream `continuous` mode, tag filtering as currently implemented, capabilities files.

## Architecture

```
grantiva (Swift CLI)
├── GrantivaCLI         # argument parsing, top-level commands
├── GrantivaCore
│   ├── Runner          # <NEW> native Swift runner
│   │   ├── FlowParser.swift       (Yams)
│   │   ├── FlowExecutor.swift     (step dispatch, retries, wait-for-idle)
│   │   ├── WDAClient.swift        (URLSession wrapper)
│   │   ├── WDALifecycle.swift     (xcodebuild, xctestrun, process)
│   │   ├── SimulatorManager.swift (mostly exists already)
│   │   └── ReportWriter.swift     (report.json)
│   ├── Config          # existing
│   └── …
└── tests               # flow-level integration tests against grantiva-examples
```

No more `scripts/build-runner.sh`, no more `scripts/grantiva-runner.patch`, no more `Sources/GrantivaCore/Resources/grantiva-runner-*.tar.gz`. The only embedded resource becomes the WDA source tree (still needed because `xcodebuild` needs a project to build), which can live as a SPM resource.

WDA source stays at `cli/Sources/GrantivaCore/Resources/WebDriverAgent/` pinned to the upstream Facebook fork version we currently ship. We apply minor xcconfig tweaks (display name rebrand from v1.0.0) directly to that checked-in copy — no patch file needed because there's no separate upstream runner to rebase against.

## Migration strategy

### Phase 1 — Parallel track (week 1–2)

- Scaffold `GrantivaCore/Runner/` with stubs.
- Implement `FlowParser` + unit tests covering every step in `grantiva-examples`.
- Implement `WDAClient` with the same surface our Go runner uses.
- Implement `WDALifecycle` + `SimulatorManager` integration.
- Implement `FlowExecutor` covering the must-have step list.

### Phase 2 — Parity gate (week 2–3)

- Add a `GRANTIVA_NATIVE_RUNNER=1` env var that routes `grantiva run` through the Swift executor instead of the Go subprocess.
- Run the full `grantiva-examples` suite under both runners. Diff `report.json`, screenshots, exit codes.
- Fix parity gaps until results are byte-identical for passing flows and equivalent error messages for failing flows.

### Phase 3 — Cutover (week 3)

- Flip the default: native Swift runner becomes the implementation, Go runner is gated behind `GRANTIVA_LEGACY_RUNNER=1`.
- Mark v2.0.0-rc1.
- Ship to early adopters (us first).
- Collect any regression signals for one to two weeks.

### Phase 4 — Removal (week 4)

- Delete `scripts/build-runner.sh`, `scripts/grantiva-runner.patch`, `Sources/GrantivaCore/Resources/grantiva-runner-*.tar.gz`.
- Delete `RunnerManager` extraction logic.
- Delete `RunnerSession` subprocess plumbing.
- Homebrew formula simplifies: no more libexec resource bundle symlink.
- Tag v2.0.0.

## Risks & mitigations

- **Flow semantics drift.** The Go runner has subtle retry / wait-for-idle heuristics we'd have to rediscover. *Mitigation:* Phase 2 parity gate against real flows, not theoretical specs. Diff actual behavior.
- **xctestrun plist injection is fragile.** Format changes between Xcode versions broke upstream at least once. *Mitigation:* keep a test fixture per Xcode version; fail fast with a clear message on format mismatch.
- **WDA compatibility.** We pin a specific WDA fork today. Apple's Xcode updates sometimes break WDA. *Mitigation:* same as today — we already own this risk. Nothing new.
- **Lose free upstream bug fixes.** The v1.0.9→v1.1.12 rebase bought us real fixes. *Mitigation:* track upstream's commit log; port specific bug fixes we need as Swift changes. Slower than rebase, but these are rare events and scoped to our actual usage.
- **Code volume.** ~5000 LOC of runner logic to write. *Mitigation:* ship iOS-only, drop 70% of upstream's surface area, lean on existing Swift libraries (Yams, URLSession).

## Success criteria

- v2.0.0 ships with `grantiva run` using the Swift-native runner by default.
- Every flow in `grantiva-examples` passes identically to v1.x behavior.
- Binary size drops by ~25 MB (the Go runner tarball delta).
- No Go toolchain required for local development.
- Next agent-facing feature (TBD) ships in < 1 hour from idea to Homebrew release.

## Open questions

- **WDA source checkout vs downloaded at install time.** Today we bundle pre-built WDA in the tarball so users don't wait for the first xcodebuild. If the Swift runner only bundles WDA source (no pre-build), the first `grantiva run` on a new machine takes an extra 2–3 minutes while WDA compiles. Do we accept that, or do we ship a pre-built WDA bundle per-Xcode-version as an SPM resource?
- **Flutter support.** We inherited it from upstream but I don't think any grantiva customer has ever used it. Confirm before dropping — or leave the door open by defining a driver-adapter interface even if we only ship the WDA adapter.
- **Parallel / multi-device execution.** Currently the Go runner has a `--parallel N` mode for running flows across N sims. Drop for v2.0 or port? Vote: drop unless a customer asks, since a wrapper script can achieve the same outcome.
