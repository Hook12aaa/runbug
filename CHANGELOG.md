# Runbug Changelog

## 0.4.1 — 2026-05-02 (build-quality fixes)

Closes the five concrete defects from the 2026-05-02 build-quality benchmark, expanded to fully close every same-class injection vector across `do.sh` / `capture.sh` / `snap.sh`, plus the doc inaccuracies the benchmark surfaced.

### Fixed

- **`do.sh` shell injection** (RCE-class). ROLE / NAME / ACTION / VALUE / NTH / ID / TAB now passed via env vars to `node -e '...'` (single-quoted), not interpolated into a heredoc. New `--print-body` flag enables server-independent regression testing.
- **`do.sh` `--tab` JSON injection** in `--wait-url` polling body — same pattern, lower severity (no RCE), now closed via env-var passing.
- **`capture.sh` `--gap` shell injection** in `node -e "...$GAP_MS..."`. Validated as a non-negative integer at flag-parse time (also covers `RUNBUG_GAP` env var).
- **`capture.sh` `$TAB` JSON injection** in 3 sites (`cleanup()`, WATCH_DOM activate, snapshot-request). All replaced with `body=$(TAB="$TAB" node -e '...')` env-var passing.
- **`snap.sh` `predicate_matches` JSON-key-order coupling**. Replaced `grep -q` against raw JSON with `JSON.parse` + recursive `tree`/`children` walk.
- **`snap.sh` `post_request` `$TAB` JSON injection** — same env-var passing as `do.sh`/`capture.sh`.
- **`shim.js` `dispatchAction` error code propagation**. `validateAxAddress` errors now carry `code: 'invalid-address'`; `resolveAx` call moved inside the try/catch so all four protocol error codes (`invalid-address`, `no-match`, `multiple-matches-need-nth`, `action-threw`) reach the action-result envelope.
- **README / `install-bridge/SKILL.md` "~80 lines" claim** — shim is actually ~250 lines. Replaced with claim-light language.
- **`CLAUDE.md` skill count** "three" → "four" (added `generate-fixtures`); fixed both the opening line and the `## The four skills` section heading + table.
- **`README.md` "What it is" prose** — "Three skills..." → "Four skills..." for consistency with the table directly below.
- **`skills/using-runbug/SKILL.md` Available Skills table** — added the missing `generate-fixtures` row; previously only listed `runbug-gate` and `install-bridge`, contradicting the top-level docs.

### Added

- `skills/install-bridge/scripts/test-injection.sh` — regression test asserting malicious payloads survive as data, not code, across 7 fields: `do.sh` NAME / ROLE / ACTION / VALUE / `--tab`; `capture.sh` `--gap`; `snap.sh` `--tab`.
- `skills/install-bridge/references/package.json` + `package-lock.json` — test-only dev-dep manifest scoped to the references directory. `"private": true`, `"type": "module"`, `jsdom` as a dev-dep. The lifted shim itself stays dependency-free.
- 5 new `dispatchAction` tests in `shim.test.js` covering each protocol error code plus the happy-path action-result.
- 2 new `test-wait-until.sh` cases: predicate match against reversed JSON key order; predicate match inside a nested `children` array.

### Changed

- Plugin version 0.4.0 → 0.4.1 (manifest + marketplace).

### Deferred to v1.4 (tracked from v0.4.1 reviews)

- `capture.sh` `sh -c "$RUNBUG_BROWSER '$BASE'"` — closes user-controlled shell injection on `RUNBUG_BROWSER` + `--url`.
- `capture.sh` `--wait` integer validation, matching the `--gap` shape.
- `snap.sh` `predicate_matches` recursion depth guard (theoretical hostile-snapshot stack overflow).
- `snap.sh` `predicate_matches` JSON.parse error surfacing — currently silent per memory `feedback_dev_mode_error_surfacing.md` ("dev-mode tools surface errors loudly").
- Multi-tab phantom-tabId issue from v1.3 dogfood (`capture.sh` refusing to start when multiple shims alive without `--tab`) — already on the v1.4 list.

## 0.4.0 — 2026-04-23 (v1.3)

`--wait-*` predicates kill the fixed-sleep pain. Multi-tab `tabId` routing closes the broadcast-confusion gap from the v1.2 dogfood. `prune-log.sh` for opt-in log retention. Drop boolean `watch_dom` (deprecated in v1.2). Modifier-key forwarding on `keydown`.

Plus the post-v1.2 patches that landed on `main` between 0.3.0 and 0.4.0: `generate-fixtures` wire envelope (`5e85a9a`), wrapping-label ANDC fix (`494b3a0`), v1.2 dogfood retro (`1f31bf0`), Vercel cookbook (`0eb5b07`).

### Added
- `skills/install-bridge/references/shim.js` — new `shouldHandleEvent(event, tabId)` export for adapter-side tab filtering.
- `createForwarder` — accepts optional `tabId`; when set, every emitted body includes the field.
- `installDomWatcher` keydown payload — four boolean fields always present: `ctrlKey`, `metaKey`, `altKey`, `shiftKey`.
- `snap.sh` — `--until-role <role>`, `--until-name <name>`, `--timeout <s>`, `--tab <id>` polling flags. AND-combinable predicates that match on the same node.
- `do.sh` — `--wait-url <prefix>`, `--timeout <s>`, `--tab <id>` flags. Flag-then-positional grammar (legacy positional still supported).
- `capture.sh --tab <id>` — explicit single-tab capture. Broadcast remains default.
- `skills/install-bridge/scripts/prune-log.sh` — opt-in `.runbug/log` retention helper.
- `skills/install-bridge/scripts/test-prune-log.sh` — POSIX-sh test for prune-log.
- `skills/install-bridge/scripts/test-wait-until.sh` — POSIX-sh test for snap.sh polling.
- v1.3 dogfood acceptance plan D1–D4 at `docs/superpowers/acceptance/2026-04-23-runbug-v1.3-dogfood.md`.

### Changed
- Wire protocol: every shim-emitted event (`shim-ready`, `console`, `dom-event`, `action-result`, `snapshot`) now carries `tabId`. Inbound events (`action`, `configure`, `snapshot-request`) MAY carry `targetTab`; absent → broadcast (v1.2 behavior preserved).
- `install-bridge/SKILL.md` Step 6 mount example — generates `tabId` via `crypto.randomUUID()`, passes to forwarders, wraps SSE handler with `shouldHandleEvent`. Version string bumped to `0.4.0`.
- `install-bridge/SKILL.md` post-install table — adds the new flags and the `prune-log.sh` row.
- `ax-protocol.md` — documents `tabId` on envelope, on `shim-ready`, on every shim-emitted event; documents `targetTab` on inbound `action`/`configure`/`snapshot-request`; adds four modifier rows on `dom-event` for `keydown`; drops boolean `watch_dom` paragraph.
- Plugin version 0.3.0 → 0.4.0 (manifest + marketplace).

### Removed
- Boolean `watch_dom` backcompat path in `configureFromEvent`. v1.2 emitted a one-time deprecation warn; v1.3 silently no-ops on boolean values. Adapters that still send `watch_dom: true` get no event delivery (and no error) — they must migrate to array form.
- Three v1.2 boolean tests: `watch_dom:true maps to`, `watch_dom:false maps to`, `boolean emits one-time deprecation warn`.

### Deferred to v1.4
- Snapshot-side AX-name truncation (v1.2 retro item 2).
- Non-sentinel values for auto-generated `input` fixtures (v1.2 deferred).
- Predicate composition beyond AND (`--until-role` + `--until-name`).
- `--wait-url` regex matching.
- `capture.sh` refusing to start when multiple shims are alive without `--tab`.

## 0.3.0 — 2026-04-23 (v1.2)

New callable `generate-fixtures` helper skill, expanded DOM-event vocabulary (`input` + `keydown`), array-shaped `watch_dom` wire protocol with boolean backcompat, capture retention flag, and v1.1 doc archival fixes.

### Added
- `skills/generate-fixtures/SKILL.md` — callable helper (no triggers). Intersects `git diff` strings with live AX snapshot; emits `fixtures.ndjson` with precision-first heuristic. Fail-open when signal is weak.
- `skills/generate-fixtures/references/worked-example.md` — frozen sample diff + snapshot + expected output; regression check.
- Wire-protocol event extras: `input.value` on textbox/searchbox/combobox; `keydown.key`.
- `capture.sh --keep-last N` — opt-in retention; prunes `.runbug/captures/*.ndjson` to newest N after each session.
- `scripts/test-retention.sh` — POSIX-sh test for retention behavior.
- v1.2 dogfood acceptance plan C1–C3 at `docs/superpowers/acceptance/2026-04-23-runbug-v1.2-dogfood.md`.

### Changed
- `configure.watch_dom` accepts an array of event-type names: `["click","submit","input","keydown"]`. Absent key = no change (unchanged). Empty array detaches all.
- Boolean `watch_dom:true|false` is a v1.1 backcompat shim that maps to `["click","submit"]` / `[]` and emits a one-time shim-side deprecation warn. Removed in v1.3.
- Shim contract: `attachDomWatcher()`/`detachDomWatcher()` replaced by `setDomWatcherEvents(array)`.
- `capture.sh` sends array-form `watch_dom` to avoid its own deprecation warn.
- `runbug-gate` EVIDENCE_MISSING path now tries `generate-fixtures` before falling back to hand-authoring, when dev server + frontend diff are both present.
- `install-bridge/SKILL.md` cross-references `generate-fixtures` in the captures section.
- `ax-protocol.md` documents `configure.watch_dom` array shape, `dom-event.eventType` enumeration expansion, and per-event `value` / `key` extras.
- Plugin version 0.2.0 → 0.3.0 (manifest + marketplace).

### Fixed
- `docs/superpowers/specs/2026-04-22-runbug-v1.1-design.md`: "bubble-phase" → "capture-phase"; `dom-event.target` schema drops the stale `nth?`. Archival, zero runtime impact.

### Deferred to v1.3
- Multi-tab session isolation (still a documented limitation).
- Removal of boolean `watch_dom` backcompat.
- Shortcut/modifier-key forwarding on `keydown` (Cmd+S, Ctrl+Enter).
- Non-sentinel values for auto-generated `input` fixtures.

## 0.2.0 — 2026-04-22 (v1.1)

Headless automation surface + opt-in DOM-event forwarding. No breaking changes to v1.0.

### Added
- `skills/install-bridge/scripts/capture.sh` — session orchestrator. Tiered browser launch (`$RUNBUG_BROWSER` → `--headless` tier → OS default), shim-ready polling, fixture-driven action dispatch, log tailing to `.runbug/captures/<ts>.ndjson`, EXIT-trap cleanup.
- `skills/install-bridge/scripts/snap.sh` — one-shot snapshot request + latest snapshot to stdout.
- `skills/install-bridge/scripts/do.sh` — single-action driver with positional args (`<role> <accessibleName> <action> [value] [nth]`) + action-result to stdout.
- `skills/install-bridge/scripts/fixtures.example.ndjson` — one-action-per-line template.
- Shim exports: `emitShimReady(forward, url, version)`, `configureFromEvent(event, shim)`, `installDomWatcher(root, forward, allowedEvents)`.
- Wire-protocol event types: `shim-ready`, `configure` (with `watch_dom:bool` session knob), `dom-event` (capture-phase `click`/`submit` while watch_dom active).
- v1.1 dogfood acceptance plan B1–B5 at `docs/superpowers/acceptance/2026-04-22-runbug-v1.1-dogfood.md`.
- Mount-wiring example for new exports in `install-bridge/SKILL.md` Step 6.
- Optional HARD-GATE I5 (don't `capture.sh --headless` against stale URLs).

### Changed
- `runbug-gate`'s EVIDENCE_MISSING Bottom Line now names the three scripts by path.
- `install-bridge` Step 7 backend contract extends to broadcasting `configure` to SSE and accepting `shim-ready` / `dom-event` on `/runbug/log`.
- `verify-bridge.sh check_i3_ax_only` honors `$RUNBUG_SHIM` env var (defect 2 fix).
- Plugin version 0.1.0 → 0.2.0 (manifest + marketplace).

### Fixed
- `capture.sh` now captures the session-initiating `shim-ready` line in its output file.
- Plan terminology corrected: capture-phase (not bubble-phase) for bubble-tracking listeners.
- `ax-protocol.md` `dom-event.target` shape matches shim emission (`{role, accessibleName}`, no `nth`).
- `ax-protocol.md` envelope `type` enumeration includes all three v1.1 types.
- `install-bridge` Step 7 per-endpoint allowlist prevents adapters from building backends that reject their own shim's events.

### Deferred to v1.2
- Auto-generated fixtures from diff/AX-intersection (item 6 territory — requires tightened AX-intersection semantics).
- Capture retention policy (`--keep-last N` / TTL) (item 7).
- `input` / `keydown` DOM-event forwarding (v1.1 only does `click` + `submit`).
- Multi-tab session isolation (currently a documented limitation).
- Archival-only spec drifts: spec doc still reads "bubble-phase" and includes `nth?` on dom-event target. Non-runtime, zero impact.
- Defect 1 (dispatchAction resolver-error throw path) — user confirmed this is working-as-intended for dev-mode tools, not a bug.

## 0.1.0 — 2026-04-22 (v1.0)

Initial release. Pre-handoff gate + three-channel console bridge for debugging interaction-triggered frontend bugs. Composes with `superpowers`. Hard dependency on superpowers plugin.

### Added
- `using-runbug` bootstrap skill — declares T1 (systematic-debugging), T2 (TDD), T3 (pre-handoff) triggers and the Playwright/browser-MCP deflection rule.
- `runbug-gate` skill — returns READY / INSTALL_NEEDED / REPAIR / EVIDENCE_MISSING / NOT_APPLICABLE / BLOCKED with 3-attempt retry caps.
- `install-bridge` skill — installs the three-channel shim (console-forward / AX-snapshot / command-channel) in whatever stack is present. Enforces HARD-GATEs I1 (dev-only activation), I2 (loop guard), I3 (AX-addressable only).
- Reference shim (`shim.js`) + 24 unit tests (`shim.test.js`).
- Wire-protocol doc (`ax-protocol.md`) for `console`, `snapshot`, `action`, `action-result` NDJSON events.
- Per-stack activation cookbook (`dev-only.md`) for Vite, Webpack, Next, Express, FastAPI, Flask, Django.
- `verify-bridge.sh` with I1/I2/I3 checks, `tail.sh` NDJSON pretty-printer.
- v1.0 dogfood acceptance plan A1–A5 and retrospective at `docs/superpowers/retrospectives/2026-04-22-runbug-v1-dogfood.md`.

### Notes
- Dogfood against the `merch` Vite webapp surfaced five items that became the v1.1 scope (items 2/3/4 → addressed in 0.2.0; items 6/7 deferred to v1.2).
- Sourcemap-aware I1 fix (exclude `*.map` from the prod-bundle fail grep, emit advisory note) shipped as a post-acceptance patch.
