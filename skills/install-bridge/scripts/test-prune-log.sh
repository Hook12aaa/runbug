#!/bin/sh
# Test prune-log.sh: seeds 100 lines, prunes to 20, asserts last 20 survive.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PRUNE_SH="$SCRIPT_DIR/prune-log.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
mkdir -p .runbug
i=1
while [ "$i" -le 100 ]; do
  echo "{\"type\":\"console\",\"ts\":\"line-$i\",\"level\":\"log\",\"args\":[]}" >> .runbug/log
  i=$((i + 1))
done

# Happy path
sh "$PRUNE_SH" --keep-last 20 >/dev/null 2>&1

remaining=$(wc -l < .runbug/log | tr -d ' ')
if [ "$remaining" != "20" ]; then
  echo "FAIL: expected 20 lines, got $remaining" >&2
  exit 1
fi

# Last 20 should be lines 81..100
first_kept=$(head -n 1 .runbug/log)
if ! echo "$first_kept" | grep -q "line-81"; then
  echo "FAIL: expected first-kept line to be line-81, got: $first_kept" >&2
  exit 1
fi

# Negative: missing flag
out=$(sh "$PRUNE_SH" 2>&1 || true)
if ! echo "$out" | grep -q "keep-last"; then
  echo "FAIL: missing flag did not produce 'keep-last' error message" >&2
  exit 1
fi

# Negative: keep-last 0
out=$(sh "$PRUNE_SH" --keep-last 0 2>&1 || true)
if ! echo "$out" | grep -q ">= 1"; then
  echo "FAIL: --keep-last 0 did not produce '>= 1' error" >&2
  exit 1
fi

# Negative: keep-last abc
out=$(sh "$PRUNE_SH" --keep-last abc 2>&1 || true)
if ! echo "$out" | grep -q "positive integer"; then
  echo "FAIL: --keep-last abc did not produce 'positive integer' error" >&2
  exit 1
fi

# Missing log: idempotent (exit 0 with stderr message)
rm .runbug/log
out=$(sh "$PRUNE_SH" --keep-last 20 2>&1)
if ! echo "$out" | grep -q "not found"; then
  echo "FAIL: missing log did not produce 'not found' message" >&2
  exit 1
fi

echo "test-prune-log: PASS"
