#!/bin/sh
# Retention flag test for capture.sh. Seeds fake capture files, invokes
# capture.sh in --test-prune-only mode (which parses --keep-last, runs the
# retention step, and exits without any browser/capture side effects), then
# asserts exactly N files remain.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAPTURE_SH="$SCRIPT_DIR/capture.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
mkdir -p .runbug/captures
touch -t 202604220001 .runbug/captures/oldest.ndjson
touch -t 202604220002 .runbug/captures/older.ndjson
touch -t 202604220003 .runbug/captures/old.ndjson
touch -t 202604220004 .runbug/captures/newer.ndjson
touch -t 202604220005 .runbug/captures/newest.ndjson

sh "$CAPTURE_SH" --keep-last 2 --test-prune-only >/dev/null 2>&1

remaining=$(ls -1 .runbug/captures/*.ndjson 2>/dev/null | wc -l | tr -d ' ')
if [ "$remaining" != "2" ]; then
  echo "FAIL: expected 2 files, got $remaining" >&2
  ls -la .runbug/captures/ >&2
  exit 1
fi

for name in newer newest; do
  if [ ! -f ".runbug/captures/$name.ndjson" ]; then
    echo "FAIL: expected $name.ndjson to survive" >&2
    exit 1
  fi
done

for name in oldest older old; do
  if [ -f ".runbug/captures/$name.ndjson" ]; then
    echo "FAIL: expected $name.ndjson to be pruned" >&2
    exit 1
  fi
done

echo "test-retention: PASS"
