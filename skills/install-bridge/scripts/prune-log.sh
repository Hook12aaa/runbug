#!/bin/sh
# Truncate .runbug/log to the last N lines. Opt-in retention helper.
# Mirrors capture.sh --keep-last N for the persistent log file.
# Usage: sh prune-log.sh --keep-last <N> [--log-path <path>]

set -eu

LOGFILE="${RUNBUG_LOG:-.runbug/log}"
KEEP_LAST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-last) KEEP_LAST="$2"; shift 2 ;;
    --log-path) LOGFILE="$2"; shift 2 ;;
    *) echo "prune-log: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$KEEP_LAST" ]; then
  echo "prune-log: --keep-last <N> is required" >&2
  exit 2
fi

case "$KEEP_LAST" in
  ''|*[!0-9]*) echo "prune-log: --keep-last expects a positive integer, got '$KEEP_LAST'" >&2; exit 2 ;;
esac

if [ "$KEEP_LAST" -lt 1 ]; then
  echo "prune-log: --keep-last must be >= 1" >&2
  exit 2
fi

if [ ! -f "$LOGFILE" ]; then
  echo "prune-log: $LOGFILE not found" >&2
  exit 0
fi

total=$(wc -l < "$LOGFILE" | tr -d ' ')
if [ "$total" -le "$KEEP_LAST" ]; then
  exit 0
fi

tail -n "$KEEP_LAST" "$LOGFILE" > "$LOGFILE.tmp"
mv "$LOGFILE.tmp" "$LOGFILE"

deleted=$((total - KEEP_LAST))
echo "prune-log: kept $KEEP_LAST, deleted $deleted" >&2
