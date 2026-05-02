# Loop Guard — I2 Reference

The shim must not forward its own errors. Without a reentrancy flag, this sequence creates an unbounded loop:

1. Shim POSTs a `console.log` event to the backend
2. Backend is down — fetch rejects
3. Catch handler calls `console.error("runbug: POST failed")`
4. Overridden `console.error` sees the call, POSTs a new event
5. That POST also fails — go to step 3

The guard breaks the cycle.

## Pattern

Every shim exposes a `guard` with `enter()` / `exit()`:

- `enter()` — returns `true` on first call, `false` on reentrance (flag already set)
- `exit()` — clears the flag; safe to call multiple times

The forwarder wraps every network send in `enter` / `finally-exit`. If `enter()` returns `false`, the forwarder silently drops the event and does not touch the network.

Additionally, the fetch error path must not call `console.*`. Any logging of forwarder failures happens in the backend, not the shim.

## Minimum spec

```javascript
function createGuard() {
  let active = false;
  return {
    enter() { if (active) return false; active = true; return true; },
    exit() { active = false; },
  };
}

function createForwarder({ endpoint, fetch, guard }) {
  return async function forward(level, args) {
    if (!guard.enter()) return;
    try {
      await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/ndjson' },
        body: JSON.stringify({ type: 'console', ts: new Date().toISOString(), level, args }),
      });
    } catch {
      // swallow — never console.* from here
    } finally {
      guard.exit();
    }
  };
}
```

## Integration test — what install-bridge must confirm

After installing the shim into a target project, `install-bridge` must:

1. Start the app in dev mode, confirm the shim is active, confirm the backend endpoint receives forwarded console events.
2. Kill the backend endpoint (stop the dev server's runbug route, or make it 503).
3. Trigger `console.error("loop-guard test")` in the browser.
4. Wait 5 seconds.
5. Confirm the browser network tab shows **at most one** failed POST (not a storm), and the page CPU is not pinned.
6. Restart the backend.

If step 5 fails, the guard is broken — halt with `REPAIR` verdict.

## Why no console.* on the error path

If the shim's fetch-error handler calls `console.error`, the overridden console (the one that forwards) sees it, sets the guard, tries to POST, fetch fails again, goes to the handler... and while the guard prevents the loop from being network-infinite, it still creates a call-stack-infinite recursion in some JS engines and burns CPU. The cleanest discipline is: **the shim is silent about its own plumbing failures.** The dev tab's native console still shows any fetch errors; the forwarder does not amplify them.
