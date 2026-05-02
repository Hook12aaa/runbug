# CLAUDE.md

This file provides guidance to Claude Code when working in the runbug plugin repository.

## Project Overview

**Runbug** is a Claude Code plugin that ships three skills — `using-runbug`, `runbug-gate`, `install-bridge` — pure markdown with a plain-JS reference shim and POSIX shell verification scripts. Claude Code is the runtime. No Python engine, no Node runtime service, no bundled headless browser.

## Hard dependency

Runbug depends on the `superpowers` plugin. Without superpowers loaded in the same environment, `runbug-gate`'s READY verdict has no consumer — there is no `systematic-debugging`, `test-driven-development`, or `verification-before-completion` skill to hand back to. Adopters must install superpowers first.

## Plugin structure

- `skills/` — `SKILL.md` files Claude loads and follows
- `hooks/` — SessionStart hook bootstraps `using-runbug`
- `.claude-plugin/` — plugin manifests

## The three skills

| Skill | Role |
|---|---|
| using-runbug | Bootstrap. Declares triggers T1/T2/T3, the Playwright/browser-MCP deflection rule, and the hard dep on superpowers. |
| runbug-gate | Fires at T1/T2/T3. Returns READY / INSTALL_NEEDED / REPAIR / EVIDENCE_MISSING / NOT_APPLICABLE / BLOCKED. |
| install-bridge | Heavy skill. Installs the three-channel shim (console-forward / AX-snapshot / command-channel) in whatever stack is present. Enforces I1 (dev-only), I2 (loop guard), I3 (AX-addressable only). |

## Triggers (when runbug-gate fires)

- **T1** — about to invoke `superpowers:systematic-debugging` on an interaction-triggered bug
- **T2** — about to invoke `superpowers:test-driven-development` on a UI interaction test
- **T3** — about to report frontend changes complete / hand off to user (the "no deflation" trigger)

## Integrity constraints

All three are `<HARD-GATE>`s at the top of `install-bridge/SKILL.md`:

- **I1** — shim and backend route exist only in dev mode; prod bundle must not contain them
- **I2** — shim's loop guard prevents its own errors from becoming forwarded errors
- **I3** — command channel accepts only `{role, accessibleName, nth?}` — no CSS selectors, no `data-testid`

## File constraint

The tooling surface is `.md` (skills, references), `.js` (reference shim), `.sh` (verification scripts). Plugin manifests are JSON (required by Claude Code).

## Composition

Runbug supplies a surface. It does not re-implement debugging, TDD, or verification methodology — those are owned by superpowers.
