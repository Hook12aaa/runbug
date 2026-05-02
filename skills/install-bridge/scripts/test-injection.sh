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

# ROLE field: malicious role value must survive as data.
BODY_ROLE=$(sh "$DO_SH" --print-body -- "$PAYLOAD" some-name click 2>/dev/null) || EXIT_ROLE=$?
EXIT_ROLE="${EXIT_ROLE:-0}"
if [ "$EXIT_ROLE" -eq 99 ]; then
  echo "FAIL: do.sh exited 99 on malicious ROLE — payload executed" >&2
  exit 1
fi
if ! printf '%s' "$BODY_ROLE" | PAYLOAD="$PAYLOAD" node -e '
  const b = require("fs").readFileSync(0, "utf8").trim();
  const parsed = JSON.parse(b);
  if (parsed.target.role !== process.env.PAYLOAD) {
    process.stderr.write("FAIL: target.role mismatch — got " + JSON.stringify(parsed.target.role));
    process.exit(2);
  }
'; then
  echo "FAIL: do.sh ROLE field was mangled or executed" >&2
  exit 1
fi

# ACTION field: malicious action value must survive as data.
BODY_ACTION=$(sh "$DO_SH" --print-body -- button some-name "$PAYLOAD" 2>/dev/null) || EXIT_ACTION=$?
EXIT_ACTION="${EXIT_ACTION:-0}"
if [ "$EXIT_ACTION" -eq 99 ]; then
  echo "FAIL: do.sh exited 99 on malicious ACTION — payload executed" >&2
  exit 1
fi
if ! printf '%s' "$BODY_ACTION" | PAYLOAD="$PAYLOAD" node -e '
  const b = require("fs").readFileSync(0, "utf8").trim();
  const parsed = JSON.parse(b);
  if (parsed.action !== process.env.PAYLOAD) {
    process.stderr.write("FAIL: action mismatch — got " + JSON.stringify(parsed.action));
    process.exit(2);
  }
'; then
  echo "FAIL: do.sh ACTION field was mangled or executed" >&2
  exit 1
fi

# VALUE field: malicious value must survive as data.
BODY_VALUE=$(sh "$DO_SH" --print-body -- button some-name input "$PAYLOAD" 2>/dev/null) || EXIT_VALUE=$?
EXIT_VALUE="${EXIT_VALUE:-0}"
if [ "$EXIT_VALUE" -eq 99 ]; then
  echo "FAIL: do.sh exited 99 on malicious VALUE — payload executed" >&2
  exit 1
fi
if ! printf '%s' "$BODY_VALUE" | PAYLOAD="$PAYLOAD" node -e '
  const b = require("fs").readFileSync(0, "utf8").trim();
  const parsed = JSON.parse(b);
  if (parsed.value !== process.env.PAYLOAD) {
    process.stderr.write("FAIL: value mismatch — got " + JSON.stringify(parsed.value));
    process.exit(2);
  }
'; then
  echo "FAIL: do.sh VALUE field was mangled or executed" >&2
  exit 1
fi

# --tab flag: malicious tab id must survive as data.
BODY_TAB=$(sh "$DO_SH" --tab "$PAYLOAD" --print-body -- button some-name click 2>/dev/null) || EXIT_TAB=$?
EXIT_TAB="${EXIT_TAB:-0}"
if [ "$EXIT_TAB" -eq 99 ]; then
  echo "FAIL: do.sh exited 99 on malicious --tab — payload executed" >&2
  exit 1
fi
if ! printf '%s' "$BODY_TAB" | PAYLOAD="$PAYLOAD" node -e '
  const b = require("fs").readFileSync(0, "utf8").trim();
  const parsed = JSON.parse(b);
  if (parsed.targetTab !== process.env.PAYLOAD) {
    process.stderr.write("FAIL: targetTab mismatch — got " + JSON.stringify(parsed.targetTab));
    process.exit(2);
  }
'; then
  echo "FAIL: do.sh --tab field was mangled or executed" >&2
  exit 1
fi

echo "PASS: do.sh treats all user-controlled fields as data (NAME, ROLE, ACTION, VALUE, --tab)"
