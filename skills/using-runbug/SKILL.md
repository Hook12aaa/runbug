---
name: using-runbug
description: Bootstrap for the runbug plugin. Auto-loaded at session start. Names the three triggers (T1 systematic-debugging, T2 TDD, T3 pre-handoff), the Playwright/browser-MCP deflection rule, and the hard dependency on superpowers. Not invoked at runtime — call runbug-gate for the actual gate.
---

# Using Runbug

Runbug is a pre-handoff gate + three-channel console bridge. It composes with superpowers to debug interaction-triggered frontend bugs without burning tokens on Playwright or browser-MCP.

## Hard Dependency

Runbug requires the `superpowers` plugin in the same environment. Without superpowers, runbug-gate's READY verdict has nowhere to hand back to — there is no `superpowers:systematic-debugging`, `superpowers:test-driven-development`, or `superpowers:verification-before-completion` skill to receive the handoff. If superpowers is not loaded, stop and tell the user to install it.

## When to Invoke runbug-gate

Invoke `runbug:runbug-gate` **BEFORE** proceeding at any of these three trigger points:

| ID | Trigger |
|---|---|
| T1 | About to invoke `superpowers:systematic-debugging` on an interaction-triggered bug (clicks, form input, drag/drop, canvas, WebGL, client-side routes, state-after-action, event-handler throws, async UI updates) |
| T2 | About to invoke `superpowers:test-driven-development` on a UI interaction test |
| T3 | About to report frontend changes complete / hand off to user — the "no deflation" trigger that prevents the "uhhh that's not it" moment |

## Deflection Rule

If about to invoke Playwright, browser-MCP, or any other browser-automation tool against a webapp the workspace hosts: **stop and invoke runbug-gate instead.** The bridge is the sensor/effector surface for this class of work; the expensive browser-automation tools are what runbug replaces, not what it supplements.

## Not Triggers

The gate must NOT fire on (and should quickly NOT_APPLICABLE if it does):

- Backend-only bugs (5xx from API, DB errors, job queue failures)
- Build / compile / type errors
- SSR or initial-render crashes surfaced in the dev-server terminal
- Pure unit tests with no DOM
- Non-web projects
- CSS-only changes with no behavior delta
- Copy edits with no interaction impact

## Available Skills

| Skill | Trigger | What it does |
|---|---|---|
| `runbug-gate` | T1 / T2 / T3 | Returns READY / INSTALL_NEEDED / REPAIR / EVIDENCE_MISSING / NOT_APPLICABLE / BLOCKED. Routes to `install-bridge` when bridge is missing or broken. |
| `install-bridge` | Invoked by runbug-gate on INSTALL_NEEDED or REPAIR | Builds the three-channel shim (console-forward / AX-snapshot / command-channel) into the target project. Enforces I1 (dev-only), I2 (loop guard), I3 (AX-addressable only). |
| `generate-fixtures` | Invoked by runbug-gate on EVIDENCE_MISSING when dev server + frontend git diff present | Intersects the git diff with a live AX snapshot to emit `fixtures.ndjson` for capture runs. Fail-open when signal is weak. |

## Core Principles

1. **Composition, not duplication.** Runbug does not re-implement debugging, TDD, or verification methodology. Those are superpowers.
2. **Protocol-first, library-last.** The wire contract in `ax-protocol.md` is the source of truth. Stack-specific plumbing (SSE, WebSocket, polling, mount point) is decided at install time.
3. **Dev-only, always.** The shim never ships to production. This is non-negotiable.
4. **AX-addressable only.** If Claude cannot reach an element by `{role, accessibleName}`, the fix is in the app code (add `aria-label`), not in the test (add `data-testid`).
5. **Capture primitives live at `install-bridge/scripts/`.** `snap.sh`, `do.sh`, and `capture.sh` are invoked by name when the gate flags `EVIDENCE_MISSING`. They are not skills and do not need to be added to the Available Skills table.

## Voice

Speak directly to the user. Do not refer to "the skill", "the gate", or third-person self-descriptions. When the gate returns a verdict, state the verdict and the next step plainly.

## Status Vocabulary

Runbug uses these verdict codes from `runbug-gate`:

- **READY** — all preconditions met; hand back to the calling superpowers skill
- **INSTALL_NEEDED** — no runbug bridge in the workspace; invoke `install-bridge`, re-gate
- **REPAIR** — bridge present but `verify-bridge.sh` failed; invoke `install-bridge` in repair mode, re-gate
- **EVIDENCE_MISSING** — T3 only; bridge is live but no capture covers the changed frontend path; drive the changed interaction, capture, re-gate
- **NOT_APPLICABLE** — not a frontend interaction concern; step aside
- **BLOCKED** — retry cap exhausted; escalate to human with specific reason (`BLOCKED_INSTALL`, `BLOCKED_REPAIR`, `BLOCKED_CAPTURE`)

## The Rule

At any moment Claude is about to work on frontend interaction behavior — invoke `runbug-gate` first. Small tweaks accumulate. The "uhhh that's not it" moment is avoidable. The gate is cheap; skipping it is expensive.
