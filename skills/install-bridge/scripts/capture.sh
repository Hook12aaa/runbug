#!/bin/sh
# Capture-session orchestrator. Launches a browser, waits for shim-ready,
# drives a fixture file of actions, tails the bridge log to an output file.
# Usage: sh capture.sh [--url <base>] [--tab <id>] [--fixtures <path>] [--out <path>] [--headless] [--watch-dom] [--wait <seconds>] [--gap <ms>] [--keep-last <N>]

set -eu

BASE="${RUNBUG_URL:-http://localhost:5173}"
LOGFILE="${RUNBUG_LOG:-.runbug/log}"
FIXTURES=""
OUT=""
HEADLESS=0
WATCH_DOM=0
WAIT_SEC="${RUNBUG_WAIT:-15}"
GAP_MS="${RUNBUG_GAP:-200}"
KEEP_LAST=""
TAB=""
TEST_PRUNE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --url) BASE="$2"; shift 2 ;;
    --fixtures) FIXTURES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --watch-dom) WATCH_DOM=1; shift ;;
    --wait) WAIT_SEC="$2"; shift 2 ;;
    --gap) GAP_MS="$2"; shift 2 ;;
    --keep-last) KEEP_LAST="$2"; shift 2 ;;
    --tab) TAB="$2"; shift 2 ;;
    --test-prune-only) TEST_PRUNE_ONLY=1; shift ;;
    *) echo "capture: unknown arg: $1" >&2; exit 2 ;;
  esac
done

prune_captures() {
  if [ -z "${KEEP_LAST:-}" ]; then return 0; fi
  case "$KEEP_LAST" in
    ''|*[!0-9]*) echo "capture: --keep-last expects a positive integer, got '$KEEP_LAST'" >&2; return 1 ;;
  esac
  if [ "$KEEP_LAST" -lt 1 ]; then
    echo "capture: --keep-last must be >= 1" >&2
    return 1
  fi
  DIR=".runbug/captures"
  [ -d "$DIR" ] || return 0
  total=$(ls -1t "$DIR"/*.ndjson 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total" -le "$KEEP_LAST" ]; then return 0; fi
  ls -1t "$DIR"/*.ndjson 2>/dev/null | tail -n +$((KEEP_LAST + 1)) | while IFS= read -r f; do
    rm -- "$f"
  done
  kept=$(ls -1 "$DIR"/*.ndjson 2>/dev/null | wc -l | tr -d ' ')
  deleted=$((total - kept))
  echo "retention: kept $kept, deleted $deleted" >&2
}

if [ "$TEST_PRUNE_ONLY" = "1" ]; then
  prune_captures
  exit 0
fi

if [ -z "$OUT" ]; then
  mkdir -p .runbug/captures
  OUT=".runbug/captures/$(date +%Y%m%dT%H%M%S).ndjson"
fi

BROWSER_PID=""
TAIL_PID=""

cleanup() {
  if [ "$WATCH_DOM" = "1" ]; then
    body='{"type":"configure","watch_dom":[]'
    if [ -n "$TAB" ]; then body="$body,\"targetTab\":\"$TAB\""; fi
    body="$body}"
    curl -sf -X POST -H 'content-type: application/json' \
      -d "$body" \
      "$BASE/runbug/commands" >/dev/null 2>&1 || true
  fi
  if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then kill "$TAIL_PID" 2>/dev/null || true; fi
  if [ -n "$BROWSER_PID" ] && kill -0 "$BROWSER_PID" 2>/dev/null; then kill "$BROWSER_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

launch_browser() {
  if [ -n "${RUNBUG_BROWSER:-}" ]; then
    sh -c "$RUNBUG_BROWSER '$BASE'" &
    BROWSER_PID=$!
    return
  fi
  if [ "$HEADLESS" = "1" ]; then
    for bin in google-chrome chromium chrome chromium-browser; do
      if command -v "$bin" >/dev/null 2>&1; then
        "$bin" --headless --disable-gpu --no-sandbox "$BASE" >/dev/null 2>&1 &
        BROWSER_PID=$!
        return
      fi
    done
    echo "capture: --headless requested but no chrome/chromium binary found" >&2
    exit 1
  fi
  case "$(uname -s)" in
    Darwin) open "$BASE"; BROWSER_PID="" ;;
    Linux) xdg-open "$BASE" >/dev/null 2>&1; BROWSER_PID="" ;;
    MINGW*|MSYS*|CYGWIN*) start "$BASE"; BROWSER_PID="" ;;
    *) echo "capture: unknown OS, set RUNBUG_BROWSER or use --headless" >&2; exit 1 ;;
  esac
}

wait_for_shim_ready() {
  deadline=$(($(date +%s) + WAIT_SEC))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ -f "$LOGFILE" ]; then
      LINE=$(tail -n 100 "$LOGFILE" | grep '"type":"shim-ready"' | tail -n 1)
      if [ -n "$LINE" ]; then
        printf '%s\n' "$LINE" >> "$OUT"
        return 0
      fi
    fi
    sleep 0.5
  done
  echo "capture: timed out after ${WAIT_SEC}s waiting for shim-ready" >&2
  exit 1
}

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
: > "$OUT"

launch_browser
wait_for_shim_ready

( tail -n 0 -f "$LOGFILE" >> "$OUT" ) &
TAIL_PID=$!

if [ "$WATCH_DOM" = "1" ]; then
  body='{"type":"configure","watch_dom":["click","submit"]'
  if [ -n "$TAB" ]; then body="$body,\"targetTab\":\"$TAB\""; fi
  body="$body}"
  curl -sf -X POST -H 'content-type: application/json' \
    -d "$body" \
    "$BASE/runbug/commands" >/dev/null
fi

if [ -n "$FIXTURES" ]; then
  if [ ! -f "$FIXTURES" ]; then
    echo "capture: fixtures file not found: $FIXTURES" >&2
    exit 1
  fi
  while IFS= read -r line; do
    case "$line" in
      '') continue ;;
      *__comment*) continue ;;
    esac
    curl -sf -X POST -H 'content-type: application/json' -d "$line" "$BASE/runbug/commands" >/dev/null
    sleep "$(node -e "process.stdout.write((($GAP_MS)/1000).toString())")"
  done < "$FIXTURES"
fi

body='{"type":"snapshot-request"'
if [ -n "$TAB" ]; then body="$body,\"targetTab\":\"$TAB\""; fi
body="$body}"
curl -sf -X POST -H 'content-type: application/json' \
  -d "$body" \
  "$BASE/runbug/commands" >/dev/null

sleep 0.5

echo "capture: wrote $OUT"
prune_captures
