#!/bin/sh
# Regression test for shell injection in do.sh and capture.sh.
# Feeds a malicious accessibleName and asserts the script treats it as data.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DO_SH="$SCRIPT_DIR/do.sh"

PAYLOAD="'); process.exit(99); //"

# Use --print-body so we don't need a running dev server.
BODY=$(sh "$DO_SH" --print-body -- button "$PAYLOAD" click 2>&1) || EXIT=$?
EXIT="${EXIT:-0}"

if [ "$EXIT" -eq 99 ]; then
  echo "FAIL: do.sh exited 99 — payload was executed as code" >&2
  exit 1
fi

# BODY must be valid JSON containing the payload as a string literal.
if ! printf '%s' "$BODY" | PAYLOAD="$PAYLOAD" node -e '
  const b = require("fs").readFileSync(0, "utf8").trim();
  const parsed = JSON.parse(b);
  if (parsed.target.accessibleName !== process.env.PAYLOAD) {
    process.stderr.write("FAIL: accessibleName mismatch — got " + JSON.stringify(parsed.target.accessibleName));
    process.exit(2);
  }
'; then
  echo "FAIL: BODY was not valid JSON or accessibleName was mangled" >&2
  echo "BODY=$BODY" >&2
  exit 1
fi

echo "PASS: do.sh treats malicious accessibleName as data"
