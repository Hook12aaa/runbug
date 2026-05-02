#!/bin/sh
# Runbug tail — pretty-print NDJSON from .runbug/log
# Usage (from target project root): sh <path-to-runbug>/scripts/tail.sh
# Output format (one event per line): <ts>  <TYPE>  <payload>

LOGFILE="${RUNBUG_LOG:-.runbug/log}"

if [ ! -f "$LOGFILE" ]; then
  echo "runbug-tail: $LOGFILE does not exist yet — waiting for shim to start writing" >&2
  mkdir -p "$(dirname "$LOGFILE")"
  : > "$LOGFILE"
fi

tail -n 0 -f "$LOGFILE" | while IFS= read -r line; do
  printf '%s\n' "$line" | node -e '
    let buf = "";
    process.stdin.on("data", (c) => { buf += c; });
    process.stdin.on("end", () => {
      try {
        const e = JSON.parse(buf.trim());
        const type = String(e.type || "?").toUpperCase().padEnd(8);
        const rest = { ...e };
        delete rest.type;
        delete rest.ts;
        console.log(`${e.ts || "no-ts"}  ${type}  ${JSON.stringify(rest)}`);
      } catch {
        console.log(`[unparseable] ${buf.trim()}`);
      }
    });
  '
done
