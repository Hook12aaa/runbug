#!/bin/sh
# Runbug install-time integrity checks. Exit 0 on pass, non-zero with named failure.
# I1 dev-only: shim not in prod bundle. I2 loop guard: reference unit tests. I3 AX-addressable: data-testid rejected.

set -eu

SHIM_IDENTIFIER="${RUNBUG_SHIM_IDENT:-runbug-shim}"
PROD_DIRS="${RUNBUG_PROD_DIRS:-dist build .next/static/chunks}"

fail() {
  echo "verify-bridge FAIL: $1" >&2
  exit 1
}

pass() {
  echo "verify-bridge: $1"
}

check_i1_prod_bundle() {
  # Exclude *.map: sourcemaps don't execute. .map hits become an advisory note, not a fail.
  any_checked=0
  map_hits=0
  map_hit_dir=""
  for dir in $PROD_DIRS; do
    if [ -d "$dir" ]; then
      any_checked=1
      if grep -r -q --exclude='*.map' "$SHIM_IDENTIFIER" "$dir" 2>/dev/null; then
        fail "I1: shim identifier '$SHIM_IDENTIFIER' found in executable production bundle at $dir"
      fi
      if grep -r -q --include='*.map' "$SHIM_IDENTIFIER" "$dir" 2>/dev/null; then
        map_hits=1
        map_hit_dir="$dir"
      fi
    fi
  done
  if [ $any_checked -eq 0 ]; then
    pass "I1: no prod bundle directories present (skipped — run after a production build to verify)"
  else
    pass "I1: prod bundle clean (executable files)"
    if [ $map_hits -eq 1 ]; then
      echo "verify-bridge: I1 note: shim identifier appears in sourcemaps under $map_hit_dir. Use sourcemap: 'hidden' or delete *.map before publishing." >&2
    fi
  fi
}

check_i2_loop_guard() {
  # Runs reference shim unit tests only. Adapted-shim outage integration test is install-bridge's responsibility — see references/loop-guard.md "Integration test" section.
  SHIM_TESTS="${RUNBUG_SHIM_TESTS:-}"
  if [ -z "$SHIM_TESTS" ]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    CANDIDATE="$SCRIPT_DIR/../references/shim.test.js"
    if [ -f "$CANDIDATE" ]; then
      SHIM_TESTS="$CANDIDATE"
    fi
  fi
  if [ -z "$SHIM_TESTS" ] || [ ! -f "$SHIM_TESTS" ]; then
    pass "I2: shim.test.js not found — skipping (run with RUNBUG_SHIM_TESTS=<path> to enable)"
    return
  fi
  if ! node --test "$SHIM_TESTS" >/tmp/runbug-shim-test.out 2>&1; then
    tail -20 /tmp/runbug-shim-test.out >&2
    fail "I2: shim unit tests failed — see output above"
  fi
  pass "I2: loop-guard unit tests passed"
}

check_i3_ax_only() {
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  SHIM="${RUNBUG_SHIM:-$SCRIPT_DIR/../references/shim.js}"
  if [ ! -f "$SHIM" ]; then
    pass "I3: shim.js not found — skipping (set RUNBUG_SHIM=<path> or install reference shim)"
    return
  fi
  RESULT=$(node -e "
    (async () => {
      const { validateAxAddress } = await import('$SHIM');
      try {
        validateAxAddress({ role: 'button', accessibleName: 'X', 'data-testid': 'y' });
        console.log('FAIL-accepted');
      } catch (e) {
        if (/not allowed/.test(e.message)) console.log('ok');
        else console.log('FAIL-wrong-message:' + e.message);
      }
    })();
  " 2>&1)
  case "$RESULT" in
    ok) pass "I3: data-testid correctly rejected" ;;
    FAIL-accepted) fail "I3: shim accepted a data-testid key — AX-only contract broken" ;;
    *) fail "I3: unexpected validator behavior: $RESULT" ;;
  esac
}

check_i1_prod_bundle
check_i2_loop_guard
check_i3_ax_only
echo "verify-bridge: all enabled checks passed"
