# Dumping the UI Hierarchy

Grantiva exposes the live UI accessibility tree of a running simulator so agents and developers can inspect state, find selectors, and diagnose failed assertions — without touching the app.

There are two ways to read the hierarchy, depending on how you started the session.

## Primary: `grantiva hierarchy` (v1.1.0+)

Pairs with `grantiva run --keep-alive`. Recommended for agent-driven flows.

```bash
# Terminal 1 (or CI background):
grantiva run --keep-alive --flow flows/onboarding.yaml

# Terminal 2 (while the session is held):
grantiva hierarchy > state.xml
# or
grantiva hierarchy --format json > state.json
```

`grantiva hierarchy` reads `~/.grantiva/runner/sessions/<udid>.json` (written by `--keep-alive`), opens an HTTP read against the running GrantivaAgent on its allocated port, and prints the XCUI accessibility tree. It does **not** create a session, launch the app, or otherwise touch the app's state. The app stays exactly where the flow left it.

If no keep-alive session is live, the command fails fast with an actionable error — it will not start a new session behind your back (which would relaunch and destroy the state you wanted to inspect).

### Output formats

- **XML (default)** — Apple's `debugDescription` format from XCUI, unwrapped from WDA's `{"value": "…"}` envelope. Full element tree with types, labels, identifiers, frames, traits.
- **JSON** — structured JSON from GrantivaAgent's `/source` endpoint.

### Flags

| Flag | Description |
|------|-------------|
| `--udid` | Target a specific simulator's session (defaults to the newest keep-alive session). |
| `--format` | `xml` (default) or `json`. |

## Alternative: `grantiva runner dump-hierarchy`

For the standalone `grantiva runner start` / `grantiva runner stop` workflow (used by the MCP server and interactive tooling):

```bash
grantiva runner start --bundle-id com.example.myapp
grantiva runner dump-hierarchy --format json
grantiva runner stop
```

This path is preserved for backward compatibility and MCP integration. New flows should prefer `grantiva run --keep-alive` + `grantiva hierarchy`, which integrate natively with flow execution.

## Agent integration

Both paths enable agent workflows like:

1. **Authoring flows** — dump the hierarchy of the screen you're writing a flow for, hand it to the agent, have it emit `tapOn`/`assertVisible` with correct identifiers.
2. **Self-healing tests** — when a flow step fails, dump the hierarchy at failure time, diff against the expected state, and propose a corrected selector.
3. **Smoke regression** — snapshot the hierarchy at known-good states, compare against future runs, flag structural drift.

## Technical details

The hierarchy comes from GrantivaAgent, a WebDriverAgent running as an `XCUITest` test runner on the simulator. The `/source` endpoint invokes `XCUIApplication.debugDescription` under the hood, which returns the current app's accessibility tree as seen by iOS's UI automation stack.

See the [full commands reference](https://docs.grantiva.io/cli/commands) for details on `grantiva run` flags, including `--keep-alive`, `--logs`, and `--flow`.
