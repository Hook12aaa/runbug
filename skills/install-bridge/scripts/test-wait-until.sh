#!/bin/sh
# Test polling-loop semantics of snap.sh --until-role / --until-name flags.
# Seeds .runbug/log with synthetic snapshot lines and asserts predicate match
# vs. timeout behavior. Runs against an unreachable URL — curl errors are
# tolerated by the polling loop.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SNAP_SH="$SCRIPT_DIR/snap.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
mkdir -p .runbug
cat > .runbug/log <<'EOF'
{"type":"shim-ready","ts":"2026-04-23T19:30:00.000Z","url":"http://localhost:5173/x","shimVersion":"0.4.0","tabId":"t1"}
{"type":"snapshot","ts":"2026-04-23T19:30:01.000Z","url":"http://localhost:5173/x","tabId":"t1","tree":[{"role":"button","accessibleName":"Save"}]}
EOF

# Case 1: predicate matches existing log → succeed quickly, exit 0.
if ! sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role button --timeout 2 >/dev/null 2>&1; then
  echo "FAIL: case 1 (predicate matches) returned non-zero" >&2
  exit 1
fi

# Case 2: predicate never matches → timeout, exit non-zero, stderr contains 'timed out'.
out=$(sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role nonexistent --timeout 1 2>&1 || true)
if ! echo "$out" | grep -q "timed out"; then
  echo "FAIL: case 2 (timeout) did not produce 'timed out' on stderr" >&2
  echo "$out" >&2
  exit 1
fi

# Case 3: --until-name combined with --until-role requires both on the same node.
cat > .runbug/log <<'EOF'
{"type":"snapshot","ts":"2026-04-23T19:30:01.000Z","url":"http://localhost:5173/x","tabId":"t1","tree":[{"role":"button","accessibleName":"Save"},{"role":"link","accessibleName":"Help"}]}
EOF

# 'Save' is a button (matches both) → succeed
if ! sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role button --until-name "Save" --timeout 2 >/dev/null 2>&1; then
  echo "FAIL: case 3a (both predicates match same node) returned non-zero" >&2
  exit 1
fi

# 'Help' is a link, not a button → AND fails
out=$(sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role button --until-name "Help" --timeout 1 2>&1 || true)
if ! echo "$out" | grep -q "timed out"; then
  echo "FAIL: case 3b (AND predicate mismatch) did not time out" >&2
  exit 1
fi

# Case 4: predicate must match regardless of JSON key order (accessibleName before role).
# Per ax-protocol.md the snapshot tree is JSON, not a wire-format with a fixed key order.
cat > .runbug/log <<'EOF'
{"type":"snapshot","ts":"2026-05-02T00:00:00.000Z","tree":[{"accessibleName":"Save","role":"button"}],"url":"http://localhost:5173/x"}
EOF
if ! sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role button --until-name "Save" --timeout 1 >/dev/null 2>&1; then
  echo "FAIL: case 4 (reversed key order: accessibleName before role) returned non-zero" >&2
  exit 1
fi

# Case 5: predicate must recurse into children per ax-protocol.md:46.
cat > .runbug/log <<'EOF'
{"type":"snapshot","ts":"2026-05-02T00:00:00.000Z","tree":[{"role":"main","accessibleName":"Page","children":[{"role":"button","accessibleName":"Save"}]}],"url":"http://localhost:5173/x"}
EOF
if ! sh "$SNAP_SH" --url http://127.0.0.1:1 --until-role button --until-name "Save" --timeout 1 >/dev/null 2>&1; then
  echo "FAIL: case 5 (predicate inside children) returned non-zero" >&2
  exit 1
fi

echo "test-wait-until: PASS"
