#!/bin/sh
# Drive one action against the running bridge and print the action-result.
# Optional --wait-url polls snapshots after action-result, succeeding when
# location.href startsWith the prefix.
# Usage: sh do.sh [--tab <id>] [--wait-url <prefix>] [--timeout <s>] -- <role> <accessibleName> <action> [value] [nth]
#        sh do.sh <role> <accessibleName> <action> [value] [nth]   (legacy short form, no flags)

set -eu

BASE="${RUNBUG_URL:-http://localhost:5173}"
LOGFILE="${RUNBUG_LOG:-.runbug/log}"
TAB=""
WAIT_URL=""
TIMEOUT=10
PRINT_BODY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --url) BASE="$2"; shift 2 ;;
    --tab) TAB="$2"; shift 2 ;;
    --wait-url) WAIT_URL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --print-body) PRINT_BODY=1; shift ;;
    --) shift; break ;;
    --*) echo "do.sh: unknown arg: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [ $# -lt 3 ]; then
  echo "do.sh: usage: [flags] [--] <role> <accessibleName> <action> [value] [nth]" >&2
  exit 2
fi

ROLE="$1"
NAME="$2"
ACTION="$3"
VALUE="${4:-}"
NTH="${5:-}"

ID="do-$(date +%s%N 2>/dev/null || date +%s)"

auto_pick_tab() {
  if [ -n "$TAB" ]; then return 0; fi
  if [ ! -f "$LOGFILE" ]; then return 0; fi
  tabs=$(tail -n 200 "$LOGFILE" 2>/dev/null \
    | grep '"type":"shim-ready"' \
    | sed -E 's/.*"tabId":"([^"]+)".*/\1/' \
    | sort -u)
  count=$(printf '%s\n' "$tabs" | grep -c . || true)
  if [ "$count" -eq 0 ]; then return 0; fi
  if [ "$count" -eq 1 ]; then TAB="$tabs"; return 0; fi
  echo "do: multiple shims alive, pass --tab <id>:" >&2
  tail -n 200 "$LOGFILE" \
    | grep '"type":"shim-ready"' \
    | sed -E 's/.*"tabId":"([^"]+)".*"url":"([^"]+)".*/  \1  \2/' \
    | sort -u >&2
  exit 3
}

auto_pick_tab

BODY=$(ROLE="$ROLE" NAME="$NAME" ACTION="$ACTION" VALUE="$VALUE" NTH="$NTH" ID="$ID" TAB="$TAB" node -e '
  const target = { role: process.env.ROLE, accessibleName: process.env.NAME };
  if (process.env.NTH) target.nth = parseInt(process.env.NTH, 10);
  const ev = { type: "action", id: process.env.ID, target, action: process.env.ACTION };
  if (process.env.VALUE) ev.value = process.env.VALUE;
  if (process.env.TAB) ev.targetTab = process.env.TAB;
  process.stdout.write(JSON.stringify(ev));
')

if [ "$PRINT_BODY" = "1" ]; then
  printf '%s\n' "$BODY"
  exit 0
fi

curl -sf -X POST -H 'content-type: application/json' -d "$BODY" "$BASE/runbug/commands" >/dev/null

sleep 0.3

if [ ! -f "$LOGFILE" ]; then
  echo "do: log file $LOGFILE not found" >&2
  exit 1
fi

RESULT=$(tail -n 100 "$LOGFILE" | grep "\"id\":\"$ID\"" | grep '"type":"action-result"' | tail -n 1)
printf '%s\n' "$RESULT"

if [ -z "$WAIT_URL" ]; then
  exit 0
fi

deadline=$(($(date +%s) + TIMEOUT))
while [ "$(date +%s)" -lt "$deadline" ]; do
  body=$(TAB="$TAB" node -e '
  const ev = { type: "snapshot-request" };
  if (process.env.TAB) ev.targetTab = process.env.TAB;
  process.stdout.write(JSON.stringify(ev));
')
  curl -sf -X POST -H 'content-type: application/json' \
    -d "$body" \
    "$BASE/runbug/commands" >/dev/null 2>&1 || true
  sleep 0.25
  latest=$(tail -n 100 "$LOGFILE" | grep '"type":"snapshot"' | tail -n 1)
  if [ -n "$latest" ]; then
    if printf '%s' "$latest" | grep -q "\"url\":\"${WAIT_URL}"; then
      exit 0
    fi
  fi
done

echo "do: --wait-url timed out after ${TIMEOUT}s waiting for url prefix '${WAIT_URL}'" >&2
exit 1
