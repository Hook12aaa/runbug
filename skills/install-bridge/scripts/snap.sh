#!/bin/sh
# Request one snapshot from the running bridge and print the latest snapshot event.
# With --until-role / --until-name, polls until a matching node appears (or --timeout fires).
# Usage: sh snap.sh [--url <base>] [--tab <id>] [--until-role <role>] [--until-name <name>] [--timeout <s>]

set -eu

BASE="${RUNBUG_URL:-http://localhost:5173}"
LOGFILE="${RUNBUG_LOG:-.runbug/log}"
UNTIL_ROLE=""
UNTIL_NAME=""
TIMEOUT=10
TAB=""

while [ $# -gt 0 ]; do
  case "$1" in
    --url) BASE="$2"; shift 2 ;;
    --tab) TAB="$2"; shift 2 ;;
    --until-role) UNTIL_ROLE="$2"; shift 2 ;;
    --until-name) UNTIL_NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "snap: unknown arg: $1" >&2; exit 2 ;;
  esac
done

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
  echo "snap: multiple shims alive, pass --tab <id>:" >&2
  tail -n 200 "$LOGFILE" \
    | grep '"type":"shim-ready"' \
    | sed -E 's/.*"tabId":"([^"]+)".*"url":"([^"]+)".*/  \1  \2/' \
    | sort -u >&2
  exit 3
}

post_request() {
  body=$(TAB="$TAB" node -e '
    const ev = { type: "snapshot-request" };
    if (process.env.TAB) ev.targetTab = process.env.TAB;
    process.stdout.write(JSON.stringify(ev));
  ')
  curl -sf -X POST -H 'content-type: application/json' \
    -d "$body" \
    "$BASE/runbug/commands" >/dev/null 2>&1 || true
}

predicate_matches() {
  if [ ! -f "$LOGFILE" ]; then return 1; fi
  latest=$(tail -n 100 "$LOGFILE" | grep '"type":"snapshot"' | tail -n 1)
  if [ -z "$latest" ]; then return 1; fi
  if [ -z "$UNTIL_ROLE" ] && [ -z "$UNTIL_NAME" ]; then return 0; fi
  UNTIL_ROLE="$UNTIL_ROLE" UNTIL_NAME="$UNTIL_NAME" SNAP="$latest" node -e '
    let snap;
    try { snap = JSON.parse(process.env.SNAP); } catch (e) { process.exit(1); }
    const role = process.env.UNTIL_ROLE || null;
    const name = process.env.UNTIL_NAME || null;
    const walk = (nodes) => {
      if (!Array.isArray(nodes)) return false;
      for (const n of nodes) {
        const roleOk = !role || n.role === role;
        const nameOk = !name || n.accessibleName === name;
        if (roleOk && nameOk) return true;
        if (n.children && walk(n.children)) return true;
      }
      return false;
    };
    process.exit(walk(snap.tree) ? 0 : 1);
  '
}

auto_pick_tab
post_request

if [ -z "$UNTIL_ROLE" ] && [ -z "$UNTIL_NAME" ]; then
  sleep 0.3
  if [ ! -f "$LOGFILE" ]; then
    echo "snap: log file $LOGFILE not found" >&2
    exit 1
  fi
  tail -n 50 "$LOGFILE" | grep '"type":"snapshot"' | tail -n 1
  exit 0
fi

deadline=$(($(date +%s) + TIMEOUT))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if predicate_matches; then
    tail -n 50 "$LOGFILE" | grep '"type":"snapshot"' | tail -n 1
    exit 0
  fi
  sleep 0.25
  post_request
done

predicate_desc=""
[ -n "$UNTIL_ROLE" ] && predicate_desc="role=$UNTIL_ROLE"
[ -n "$UNTIL_NAME" ] && predicate_desc="$predicate_desc name=$UNTIL_NAME"
echo "snap: timed out after ${TIMEOUT}s waiting for ${predicate_desc}" >&2
exit 1
