# Runbug

A Claude Code plugin that gives Claude a thin runtime channel into a frontend dev server — so it can drive and verify a web app by accessibility role/name instead of standing up a chromium controller.

## Why I built this

Claude Code is genuinely good at one half of the job: exposing problems in code itself. Architectural faults, broken contracts, type errors, failing unit and build tests — anywhere the bug surface lines up with the static surface, Claude can read the project and tell you what's wrong.

Frontend is the other half. When the runtime is the browser — Three.js, WebGL, Fabric.js, a client-side state machine, anything where the bug only shows up once the code is *running* and someone is *interacting* — reading the source isn't enough. Claude needs to actually drive the app to know whether a change worked. The default reflex for that is Playwright or Selenium: a second runtime, a second browser instance, and a token budget that gets eaten standing the harness up before a single assertion runs.

Runbug exists to compress that loop. The premise is simple: the dev server is already running, the page is already mounted, and Claude is already the runtime for the conversation. The missing piece is a thin channel — console out, an accessibility-tree snapshot in, and a command pipe that addresses elements by `{role, name}` rather than CSS selectors. Dev-mode-only JS, no production footprint.

The result is a faster proof-of-concept and validation loop for ideas built with Claude Code: fewer tokens per interaction, no second browser, and the agent can move around the app under test instead of guessing whether its fix landed.

## What it is

Four skills, one reference shim, a small set of POSIX-sh verification scripts. Claude Code is the runtime — most of the surface is markdown.

| Surface | Role |
|---|---|
| `using-runbug` | Bootstrap. Loads at session start, declares the three triggers, deflects Playwright / browser-MCP. |
| `runbug-gate` | Pre-handoff gate. Fires before interaction debugging, before UI tests, and before "frontend is done." Returns READY / INSTALL_NEEDED / REPAIR / EVIDENCE_MISSING / NOT_APPLICABLE / BLOCKED. |
| `install-bridge` | Installs the three-channel shim into the target project: console-forward, AX-snapshot, command-channel. Dev-mode only, with a loop guard, AX-addressable only. |
| `generate-fixtures` | Callable helper. Intersects the current git diff with a live AX snapshot to produce `fixtures.ndjson` for capture runs. |
| `shim.js` (reference) | Plain JS, no dependencies. Stack adapters (Vite, Next, etc.) reduce to thin wrappers around this. |

## Triggers

`runbug-gate` fires at three points:

- **T1** — about to invoke `superpowers:systematic-debugging` on an interaction-triggered bug.
- **T2** — about to invoke `superpowers:test-driven-development` on a UI interaction test.
- **T3** — about to report frontend changes complete or hand off to the user.

## Integrity rails

Three hard gates the install enforces:

- **I1** — the shim and its backend route exist only in dev mode. The production bundle must not contain them.
- **I2** — the shim's loop guard prevents its own errors from being forwarded back as new errors.
- **I3** — the command channel accepts only `{role, accessibleName, nth?}`. No CSS selectors. No `data-testid`.

## Composition

Runbug owns the evidence surface. It does not own debugging methodology, TDD methodology, or pre-completion verification — those are owned by the `superpowers` plugin. Runbug has a hard dependency on superpowers: without it, a `READY` verdict has no consumer. Install superpowers first.

## License

MIT.
