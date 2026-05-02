# Worked Example — generate-fixtures

This file is the canonical consistency check for `generate-fixtures`. When the skill's procedure changes, apply the change to the diff + snapshot below and verify the expected output still matches. If it diverges, either the procedure regressed or the example needs updating intentionally.

## Sample diff

A small edit to a fictional `MerchEditor.jsx` component — adds a reset button and renames an existing textbox placeholder.

```
diff --git a/src/MerchEditor.jsx b/src/MerchEditor.jsx
index abc1234..def5678 100644
--- a/src/MerchEditor.jsx
+++ b/src/MerchEditor.jsx
@@ -12,7 +12,11 @@ export function MerchEditor() {
   return (
     <form>
-      <input placeholder="Text goes here" />
+      <input placeholder="Caption" aria-label="Caption" />
       <button>Add text</button>
+      <button type="button" onClick={handleReset}>Reset design</button>
       <button type="submit">Save</button>
     </form>
   );
 }
```

## Sample AX snapshot

Snapshot of the rendered `MerchEditor` at `http://localhost:5173/design`.

```json
{
  "type": "snapshot",
  "ts": "2026-04-23T19:30:00.000Z",
  "url": "http://localhost:5173/design",
  "tree": [
    { "role": "form", "accessibleName": "Design form",
      "children": [
        { "role": "textbox", "accessibleName": "Caption" },
        { "role": "button", "accessibleName": "Add text" },
        { "role": "button", "accessibleName": "Reset design" },
        { "role": "button", "accessibleName": "Save" }
      ]
    }
  ]
}
```

## Candidate extraction (Step 3 of SKILL.md)

From the diff, extracted strings (filtered to ≥2 chars, non-identifier, non-path):

- `Text goes here` (from the `-` line — placeholder)
- `Caption` (from `+` line — placeholder and aria-label)
- `Add text` (JSX text child, unchanged line in the hunk but inside the diff window — include conservatively)
- `Reset design` (JSX text child, `+` line)
- `Save` (JSX text child, unchanged context line — include if within diff window, otherwise skip)

## Intersection (Step 4-5)

Matched against the snapshot:

- `Caption` → matches `textbox` node → keep
- `Add text` → matches `button` node → keep
- `Reset design` → matches `button` node → keep
- `Save` → matches `button` node → keep (if included in candidates)
- `Text goes here` → no match in current snapshot → skip (the placeholder was renamed)

No ambiguous pairs.

## Expected fixture output

`.runbug/fixtures.ndjson`:

```
{"type":"action","id":"f1","target":{"role":"textbox","accessibleName":"Caption"},"action":"input","value":"runbug-probe"}
{"type":"action","id":"f2","target":{"role":"button","accessibleName":"Add text"},"action":"click"}
{"type":"action","id":"f3","target":{"role":"button","accessibleName":"Reset design"},"action":"click"}
{"type":"action","id":"f4","target":{"role":"button","accessibleName":"Save"},"action":"click"}
```

## Expected stdout summary

```
generated 4 fixtures from 5 diff candidates (0 ambiguous, skipped)
```

## Regression notes

- If the procedure ever starts emitting `nth`, the output diverges — this example has no ambiguous pairs, so `nth` should never appear.
- If the procedure drops the "≥2 chars" filter, irrelevant single-char diff tokens (like `</` or `"`) start appearing as candidates.
- If the procedure loosens the intersection to substring matching, `Text goes` (from `Text goes here`) could spuriously match nothing in this example but would hit noisy false positives in larger diffs.
