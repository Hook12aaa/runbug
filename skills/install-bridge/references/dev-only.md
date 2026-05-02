# Dev-Only Activation — I1 Cookbook

The shim and backend route must exist only when the stack's dev flag is set. Production builds must not contain them.

For each supported stack, use the activation guard and prod-bundle grep pattern below. If the target is a stack not listed here, pick the closest analogue — the principle is constant even when the syntax varies.

## Vite (React, Vue, Svelte, vanilla)

**Activation guard (JS import):**
```javascript
if (import.meta.env.DEV) {
  import('./runbug-shim.js');
}
```

**Prod-bundle grep (verify-bridge.sh):**
```sh
! grep -r "runbug-shim" dist/ 2>/dev/null
```

Build with `vite build`. `import.meta.env.DEV` is replaced with `false` by the build, so the `if` branch is dead code and tree-shaken.

## Webpack (CRA, custom)

**Activation guard:**
```javascript
if (process.env.NODE_ENV === 'development') {
  require('./runbug-shim.js');
}
```

**Prod-bundle grep:**
```sh
! grep -r "runbug-shim" build/ dist/ 2>/dev/null
```

`process.env.NODE_ENV` is replaced with `"production"` in prod builds by DefinePlugin.

## Next.js

**Activation guard (app entry or layout):**
```javascript
if (process.env.NODE_ENV === 'development') {
  import('./runbug-shim.js');
}
```

**Prod-bundle grep:**
```sh
! grep -r "runbug-shim" .next/static/chunks/ 2>/dev/null
```

## Vercel-deployed projects (Vite-based frontend or similar)

**Do not mount the runbug backend as a Vercel function.** Vercel functions are request-scoped and do not sustain SSE reliably — each invocation has a finite execution boundary, after which the stream severs mid-session. Mount the bridge in the long-lived dev-server middleware substrate instead.

For Vite-based projects, expose the bridge from a `configureServer` middleware inside `vite.config.js`:

```javascript
// vite.config.js
import fs from 'node:fs';

const runbugPlugin = () => {
  const clients = new Set();
  return {
    name: 'runbug-bridge',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/runbug/log', (req, res, next) => {
        if (req.method !== 'POST') return next();
        let body = '';
        req.on('data', (c) => (body += c));
        req.on('end', () => {
          fs.appendFileSync('.runbug/log', body + '\n');
          res.statusCode = 200;
          res.end('ok');
        });
      });
      server.middlewares.use('/runbug/commands', (req, res, next) => {
        if (req.method === 'GET') {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            Connection: 'keep-alive',
          });
          clients.add(res);
          req.on('close', () => clients.delete(res));
        } else if (req.method === 'POST') {
          let body = '';
          req.on('data', (c) => (body += c));
          req.on('end', () => {
            for (const c of clients) c.write(`data: ${body}\n\n`);
            res.statusCode = 200;
            res.end('ok');
          });
        } else next();
      });
    },
  };
};

export default { plugins: [runbugPlugin()] };
```

`apply: 'serve'` ensures the plugin only loads in dev — `vite build` strips it. The frontend activation guard is the same as the vanilla Vite section above (`if (import.meta.env.DEV) ...`).

**Prod-bundle grep (verify-bridge.sh):**
```sh
! grep -r "runbug-shim" dist/ 2>/dev/null
! grep -r "runbug-bridge" dist/ 2>/dev/null
```

The second grep catches accidental imports of the plugin from runtime code paths. The shim identifier is `runbug-shim`; the plugin name is `runbug-bridge`.

For non-Vite Vercel stacks (SvelteKit, Astro, Next.js), the rule is constant: mount the bridge in the dev server's persistent middleware hook — never in a serverless function.

## Express (backend — runbug endpoint)

**Activation guard (in server entry):**
```javascript
if (process.env.NODE_ENV !== 'production') {
  const runbugRouter = require('./runbug-router');
  app.use('/runbug', runbugRouter);
}
```

**Prod-bundle grep (source tree, since Express usually not bundled):**
```sh
# Verify the route is guarded by NODE_ENV, not unconditionally mounted
grep -A1 "runbug-router" server.js | grep -q "NODE_ENV"
```

## FastAPI (backend)

**Activation guard:**
```python
if app.debug:
    from .runbug_router import router as runbug_router
    app.include_router(runbug_router, prefix="/runbug")
```

Note: the `.py` file lives in the TARGET project — runbug itself ships no Python.

## Flask (backend)

**Activation guard:**
```python
if app.debug:
    from .runbug_router import runbug_bp
    app.register_blueprint(runbug_bp, url_prefix="/runbug")
```

## Django (backend)

**Activation guard (`urls.py`):**
```python
if settings.DEBUG:
    urlpatterns += [path("runbug/", include("runbug_app.urls"))]
```

## If the stack is not listed

The pattern is always:

1. A dev-mode conditional that the build tool / runtime can evaluate at build or startup
2. A prod-bundle (or prod-deploy) grep that fails if the shim's identifier leaks into production output

When adapting to an unlisted stack, `install-bridge` must document the chosen guard and grep pattern in the target project's generated `.runbug/install-notes.md` so `verify-bridge.sh` can run the correct check.
