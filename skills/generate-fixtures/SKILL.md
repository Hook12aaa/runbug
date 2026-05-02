---
name: generate-fixtures
description: Callable helper. Produces fixtures.ndjson from the intersection of a git diff and a live AX snapshot. Invoked by reference from runbug-gate, install-bridge, or Claude direct — has no triggers. Fail-open: emits nothing when signal is weak, so the caller falls back to hand-authoring.
---

# Generate Fixtures

<HARD-GATE>
This skill is called. It does not fire on triggers. If you found yourself here without a caller explicitly delegating, stop and check who needs this.
</HARD-GATE>

<HARD-GATE>
Precision-first, never broad. Emit fixtures ONLY for interactive elements whose accessibleName appears in the diff. If zero matches, emit nothing. Never guess. Never synthesize.
</HARD-GATE>

## Role

Produce `.runbug/fixtures.ndjson` (or the caller's chosen path) by intersecting two signals:
1. Strings a developer just changed (from `git diff`).
2. Accessible-name values a user can currently reach (from `snap.sh`).

The overlap is the set of interactive surfaces most likely affected by the change. Everything else is noise for the purposes of exercising a diff.

## Inputs the caller supplies

| Input | Default | Notes |
|---|---|---|
| Dev server URL | (required) | Passed to `skills/install-bridge/scripts/snap.sh`. |
| Diff source | `git diff HEAD` | Overridable: staged, unstaged, or a rev range like `git diff main..HEAD`. |
| Output path | `.runbug/fixtures.ndjson` | Parent dirs created if missing. |

## Procedure

1. **Snapshot.** Run `sh <plugin>/skills/install-bridge/scripts/snap.sh --url <URL>` and parse the `snapshot` event. Abort with the fail-open path if snap.sh fails or returns no tree.

2. **Diff.** Capture the diff text from the configured source. Abort with the fail-open path if empty.

3. **Candidate extraction.** From the diff, extract strings that could plausibly be accessible names. Include:
   - JSX text children (text sitting between tags: `<button>Add text</button>`).
   - Values of `aria-label`, `aria-labelledby`, `placeholder`, `title`, `alt`.
   - String literals inside quoted expressions (single, double, template with no interpolation).

   Exclude:
   - Identifiers (variable/function/component names).
   - Import specifiers, file paths, module names.
   - CSS class names and inline style strings.
   - Numeric-only strings.
   - Strings shorter than 2 characters.

4. **Intersection.** Walk the AX snapshot. For each node, collect `(role, accessibleName)` where `accessibleName` matches a candidate by:
   - case-sensitive exact match, OR
   - match after normalizing whitespace (collapse runs of whitespace to a single space; trim ends).

5. **Dedupe.** If two distinct AX nodes share the same `(role, accessibleName)` pair, drop BOTH. The heuristic has no basis for choosing between them and emitting `nth` for ambiguity resolution is not part of this skill's contract.

6. **Emit.** For each surviving `(role, accessibleName)` pair, write one JSON object per line to the output path. Each line is an `action` envelope per the wire protocol: required `type:"action"`, a session-unique `id` (use sequential `f1`, `f2`, …), `target` (the AX address), and `action`. Role determines the action verb:

   | Role | Action | Extra field |
   |---|---|---|
   | `button`, `link`, `checkbox`, `menuitem` | `click` | — |
   | `textbox`, `searchbox`, `combobox` | `input` | `value: "runbug-probe"` |
   | `form` | (skip — submission is exercised by clicking a submit button) | — |
   | (anything else) | `click` | — |

   Line shape:
   ```
   {"type":"action","id":"f1","target":{"role":"button","accessibleName":"Add text"},"action":"click"}
   ```

7. **Summary.** Print one line to stdout:
   ```
   generated <N> fixtures from <M> diff candidates (<K> ambiguous, skipped)
   ```

## Fail-open contract

Never produce synthetic or guessed fixtures. Write NOTHING and print one of these lines (exit 0 in all cases — the caller treats "tried, got nothing" as normal):

| Condition | Line |
|---|---|
| Diff source produced empty output | `no fixtures generated: empty diff` |
| snap.sh unavailable or returned no AX tree | `no fixtures generated: snapshot unavailable` |
| Candidates extracted but no AX matches | `no fixtures generated: no diff-named elements in snapshot` |

## I3 invariant

Fixtures emit only `{role, accessibleName}` pairs. No CSS selectors. No `data-testid`. No `nth`. Matches the shim's I3 address shape exactly. Ambiguity resolves by dropping both matches, not by emitting `nth`.

## Output path hygiene

- Create parent directories if they don't exist.
- Overwrite the output path without asking. The caller owns versioning.
- Write one JSON object per line. No trailing newline. No leading comments. Keep the file shape identical to what `capture.sh --fixtures` consumes.

## Self-verification

`references/worked-example.md` carries a frozen triple (sample diff + sample snapshot + expected fixture output). Before modifying this skill, apply the updated procedure to the example and confirm the output still matches. Regression guard for non-obvious rule changes.

## Gate Functions

- BEFORE writing any fixture line: "Does this element's accessibleName actually appear in the diff text, or am I rationalizing a proximity match?"
- BEFORE choosing an action: "Does the role table above cover this element's role, or am I improvising?"
- BEFORE emitting `nth`: stop. `nth` is never emitted. Drop the ambiguous pair.
- BEFORE synthesizing a string: stop. Write the fail-open line instead.

## Rationalization Table

| You think... | Reality |
|---|---|
| "The diff mentions a button but the snapshot doesn't have it — I'll add it to fixtures anyway" | The shim can't address what's not in the snapshot. Your fixture will fail with `no-match`. Skip. |
| "Two buttons share the name; I'll emit the first one" | Ambiguity is not resolved by ordinal position. Drop both. If the user needs them exercised separately, they must hand-author with `nth`. |
| "The diff is empty but I can guess likely interactions from file names" | Guessing is the failure mode this skill exists to avoid. Fail-open. |
| "The candidate string is only 1 character, but it's a meaningful label" | 2-char minimum is a false-positive filter, not a correctness rule. If a 1-char label is real, the user can hand-author. |
| "I'll generate fixtures for non-diff-named elements too, just to increase coverage" | Breaks precision-first. Not this skill. |

## Red Flags

- Emitting a fixture for an element whose accessibleName doesn't appear literally in the diff.
- Using CSS selectors, `data-testid`, or `nth` in any fixture line.
- Writing synthetic placeholder actions when the diff is empty.
- Silent partial-file writes when snap.sh times out mid-walk.

## Key Principles

- **Claude is the runtime.** No sub-scripts. This skill is read by Claude and executed by Claude, using the existing shell primitives (`snap.sh`, `git diff`).
- **Precision over recall.** Miss-rather-than-guess. Recall is covered by the shim's capture log during use.
- **Fail-open.** Zero matches is a valid outcome; the caller already has a fallback path (hand-authoring).
- **I3-only shape.** Fixtures must round-trip through the same shim I3 address validator.

## The Bottom Line

Write fixtures to the configured path (default `.runbug/fixtures.ndjson`). Print one of:

- `generated <N> fixtures from <M> diff candidates (<K> ambiguous, skipped)` — success
- `no fixtures generated: empty diff` — fail-open
- `no fixtures generated: snapshot unavailable` — fail-open
- `no fixtures generated: no diff-named elements in snapshot` — fail-open

Return to the caller.
