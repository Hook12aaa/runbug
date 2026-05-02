import test from 'node:test';
import assert from 'node:assert/strict';
import { createGuard, createForwarder } from './shim.js';

test('guard enter returns true on first call', () => {
  const g = createGuard();
  assert.equal(g.enter(), true);
});

test('guard enter returns false while active', () => {
  const g = createGuard();
  g.enter();
  assert.equal(g.enter(), false);
});

test('guard exit allows re-entry', () => {
  const g = createGuard();
  g.enter();
  g.exit();
  assert.equal(g.enter(), true);
});

test('guard exit is safe to call when inactive', () => {
  const g = createGuard();
  assert.doesNotThrow(() => g.exit());
});

test('forwarder sends console event to endpoint', async () => {
  const calls = [];
  const fakeFetch = async (url, opts) => { calls.push({ url, opts }); return { ok: true }; };
  const forward = createForwarder({ endpoint: '/runbug/log', fetch: fakeFetch, guard: createGuard() });
  await forward('log', ['hello']);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, '/runbug/log');
  const body = JSON.parse(calls[0].opts.body);
  assert.equal(body.type, 'console');
  assert.equal(body.level, 'log');
  assert.deepEqual(body.args, ['hello']);
});

test('forwarder skips when guard already active', async () => {
  const calls = [];
  const fakeFetch = async (url, opts) => { calls.push({ url, opts }); return { ok: true }; };
  const guard = createGuard();
  guard.enter();
  const forward = createForwarder({ endpoint: '/runbug/log', fetch: fakeFetch, guard });
  await forward('error', ['recursive!']);
  assert.equal(calls.length, 0);
});

test('forwarder swallows fetch errors without rethrowing', async () => {
  const fakeFetch = async () => { throw new Error('network down'); };
  const guard = createGuard();
  const forward = createForwarder({ endpoint: '/runbug/log', fetch: fakeFetch, guard });
  await assert.doesNotReject(() => forward('log', ['hello']));
});

test('forwarder releases guard after fetch error', async () => {
  const fakeFetch = async () => { throw new Error('network down'); };
  const guard = createGuard();
  const forward = createForwarder({ endpoint: '/runbug/log', fetch: fakeFetch, guard });
  await forward('log', ['hello']);
  assert.equal(guard.enter(), true, 'guard should be released after forwarder errors');
});

test('forwarder stamps ISO 8601 timestamp', async () => {
  const calls = [];
  const fakeFetch = async (url, opts) => { calls.push({ url, opts }); return { ok: true }; };
  const forward = createForwarder({ endpoint: '/runbug/log', fetch: fakeFetch, guard: createGuard() });
  await forward('log', ['hello']);
  const body = JSON.parse(calls[0].opts.body);
  assert.match(body.ts, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
});

import { validateAxAddress } from './shim.js';

test('validateAxAddress accepts {role, accessibleName}', () => {
  assert.doesNotThrow(() => validateAxAddress({ role: 'button', accessibleName: 'Play' }));
});

test('validateAxAddress accepts {role, accessibleName, nth}', () => {
  assert.doesNotThrow(() => validateAxAddress({ role: 'button', accessibleName: 'Play', nth: 2 }));
});

test('validateAxAddress rejects data-testid', () => {
  assert.throws(
    () => validateAxAddress({ role: 'button', accessibleName: 'Play', 'data-testid': 'x' }),
    /not allowed/,
  );
});

test('validateAxAddress rejects css selector key', () => {
  assert.throws(
    () => validateAxAddress({ role: 'button', accessibleName: 'Play', selector: '.btn' }),
    /not allowed/,
  );
});

test('validateAxAddress rejects missing role', () => {
  assert.throws(() => validateAxAddress({ accessibleName: 'Play' }), /role is required/);
});

test('validateAxAddress rejects empty role', () => {
  assert.throws(() => validateAxAddress({ role: '', accessibleName: 'Play' }), /role is required/);
});

test('validateAxAddress rejects missing accessibleName', () => {
  assert.throws(() => validateAxAddress({ role: 'button' }), /accessibleName is required/);
});

test('validateAxAddress rejects empty accessibleName', () => {
  assert.throws(
    () => validateAxAddress({ role: 'button', accessibleName: '' }),
    /accessibleName is required/,
  );
});

test('validateAxAddress rejects negative nth', () => {
  assert.throws(
    () => validateAxAddress({ role: 'button', accessibleName: 'Play', nth: -1 }),
    /nth.*non-negative integer/,
  );
});

test('validateAxAddress rejects non-integer nth', () => {
  assert.throws(
    () => validateAxAddress({ role: 'button', accessibleName: 'Play', nth: 1.5 }),
    /nth.*non-negative integer/,
  );
});

test('validateAxAddress rejects non-object input', () => {
  assert.throws(() => validateAxAddress(null), /must be an object/);
  assert.throws(() => validateAxAddress('button'), /must be an object/);
});

// DOM-dependent functions are integration-tested by verify-bridge.sh in the target project.
import * as shim from './shim.js';

test('shim exports resolveAx', () => {
  assert.equal(typeof shim.resolveAx, 'function');
});

test('shim exports dispatchAction', () => {
  assert.equal(typeof shim.dispatchAction, 'function');
});

test('shim exports installConsoleProxy', () => {
  assert.equal(typeof shim.installConsoleProxy, 'function');
});

test('resolveAx validates address before DOM access', () => {
  assert.throws(
    () => shim.resolveAx({ role: 'button', accessibleName: 'X', 'data-testid': 'y' }, null),
    /not allowed/,
  );
});

import { emitShimReady } from './shim.js';

test('emitShimReady forwards shim-ready event with url and version', () => {
  const calls = [];
  const fakeForward = (type, payload) => { calls.push({ type, payload }); };
  emitShimReady(fakeForward, 'http://localhost:5173/design', '0.2.0');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].type, 'shim-ready');
  assert.equal(calls[0].payload.url, 'http://localhost:5173/design');
  assert.equal(calls[0].payload.shimVersion, '0.2.0');
});

test('emitShimReady rejects missing url', () => {
  const fakeForward = () => {};
  assert.throws(() => emitShimReady(fakeForward, '', '0.2.0'), /url is required/);
  assert.throws(() => emitShimReady(fakeForward, null, '0.2.0'), /url is required/);
});

test('emitShimReady rejects missing version', () => {
  const fakeForward = () => {};
  assert.throws(() => emitShimReady(fakeForward, 'http://x', ''), /version is required/);
  assert.throws(() => emitShimReady(fakeForward, 'http://x', null), /version is required/);
});

import { configureFromEvent } from './shim.js';

test('configureFromEvent with array watch_dom calls setDomWatcherEvents with array', () => {
  const calls = [];
  const shim = { setDomWatcherEvents: (arr) => calls.push(arr) };
  configureFromEvent({ type: 'configure', watch_dom: ['click', 'input'] }, shim);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], ['click', 'input']);
});

test('configureFromEvent with empty array watch_dom calls setDomWatcherEvents with []', () => {
  const calls = [];
  const shim = { setDomWatcherEvents: (arr) => calls.push(arr) };
  configureFromEvent({ type: 'configure', watch_dom: [] }, shim);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], []);
});

test('configureFromEvent without watch_dom does not touch watcher', () => {
  const calls = [];
  const shim = { setDomWatcherEvents: (arr) => calls.push(arr) };
  configureFromEvent({ type: 'configure' }, shim);
  assert.equal(calls.length, 0);
});

test('validateAxAddress errors carry code: invalid-address', () => {
  try { validateAxAddress(null); assert.fail('should throw'); }
  catch (e) { assert.equal(e.code, 'invalid-address'); }
  try { validateAxAddress({ role: 'button', accessibleName: 'X', extra: 1 }); assert.fail('should throw'); }
  catch (e) { assert.equal(e.code, 'invalid-address'); }
  try { validateAxAddress({ role: '', accessibleName: 'X' }); assert.fail('should throw'); }
  catch (e) { assert.equal(e.code, 'invalid-address'); }
  try { validateAxAddress({ role: 'button', accessibleName: '' }); assert.fail('should throw'); }
  catch (e) { assert.equal(e.code, 'invalid-address'); }
  try { validateAxAddress({ role: 'button', accessibleName: 'X', nth: -1 }); assert.fail('should throw'); }
  catch (e) { assert.equal(e.code, 'invalid-address'); }
});

test('configureFromEvent ignores unknown keys without throwing', () => {
  const calls = [];
  const shim = { setDomWatcherEvents: (arr) => calls.push(arr) };
  assert.doesNotThrow(() => configureFromEvent({ type: 'configure', future_knob: 42 }, shim));
  assert.equal(calls.length, 0);
});

import { installDomWatcher } from './shim.js';

test('installDomWatcher exports as function', () => {
  assert.equal(typeof installDomWatcher, 'function');
});

test('installDomWatcher returns a detach function', () => {
  const fakeRoot = { addEventListener: () => {}, removeEventListener: () => {} };
  const detach = installDomWatcher(fakeRoot, () => {}, ['click']);
  assert.equal(typeof detach, 'function');
});

test('installDomWatcher attaches listeners for each allowed event type', () => {
  const attached = [];
  const fakeRoot = {
    addEventListener: (t) => attached.push(t),
    removeEventListener: () => {},
  };
  installDomWatcher(fakeRoot, () => {}, ['click', 'submit']);
  assert.deepEqual(attached, ['click', 'submit']);
});

test('installDomWatcher detach removes every attached listener', () => {
  const attached = [];
  const removed = [];
  const fakeRoot = {
    addEventListener: (t) => attached.push(t),
    removeEventListener: (t) => removed.push(t),
  };
  const detach = installDomWatcher(fakeRoot, () => {}, ['click', 'submit']);
  detach();
  assert.deepEqual(removed.sort(), ['click', 'submit']);
});

test('installDomWatcher: input event on textbox emits value', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['input']);
  const fakeTextbox = {
    getAttribute: (k) => k === 'placeholder' ? 'Your name' : null,
    hasAttribute: () => false,
    tagName: 'INPUT',
    value: 'hello world',
    textContent: '',
    ownerDocument: null,
  };
  handlers.input({ target: fakeTextbox });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.eventType, 'input');
  assert.equal(events[0].payload.target.role, 'textbox');
  assert.equal(events[0].payload.target.accessibleName, 'Your name');
  assert.equal(events[0].payload.value, 'hello world');
});

test('installDomWatcher: input event on non-text role omits value', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['input']);
  const fakeCheckbox = {
    getAttribute: (k) => {
      if (k === 'aria-label') return 'Agree';
      if (k === 'type') return 'checkbox';
      return null;
    },
    hasAttribute: () => false,
    tagName: 'INPUT',
    value: 'on',
    textContent: '',
    ownerDocument: null,
  };
  handlers.input({ target: fakeCheckbox });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.target.role, 'checkbox');
  assert.equal('value' in events[0].payload, false, 'value should be omitted for non-text roles');
});

test('installDomWatcher: keydown event emits key field', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['keydown']);
  const fakeInput = {
    getAttribute: (k) => k === 'placeholder' ? 'Search' : null,
    hasAttribute: () => false,
    tagName: 'INPUT',
    textContent: '',
    ownerDocument: null,
  };
  handlers.keydown({ target: fakeInput, key: 'Enter' });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.eventType, 'keydown');
  assert.equal(events[0].payload.key, 'Enter');
  assert.equal(events[0].payload.ctrlKey, false);
  assert.equal(events[0].payload.metaKey, false);
  assert.equal(events[0].payload.altKey, false);
  assert.equal(events[0].payload.shiftKey, false);
});


test('installDomWatcher: input wrapped in <label> resolves accessibleName from the label', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['click']);

  const fakeLabel = {
    tagName: 'LABEL',
    textContent: 'Agree to terms',
    parentElement: null,
  };
  const fakeCheckbox = {
    getAttribute: (k) => k === 'type' ? 'checkbox' : null,
    hasAttribute: () => false,
    tagName: 'INPUT',
    textContent: '',
    ownerDocument: null,
    parentElement: fakeLabel,
  };

  handlers.click({ target: fakeCheckbox });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.target.role, 'checkbox');
  assert.equal(events[0].payload.target.accessibleName, 'Agree to terms');
});

test('installDomWatcher: keydown emits all four modifier booleans always (with one held)', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['keydown']);
  const fakeInput = {
    getAttribute: (k) => k === 'placeholder' ? 'Search' : null,
    hasAttribute: () => false,
    tagName: 'INPUT',
    textContent: '',
    ownerDocument: null,
  };
  handlers.keydown({
    target: fakeInput,
    key: 's',
    ctrlKey: false,
    metaKey: true,
    altKey: false,
    shiftKey: false,
  });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.key, 's');
  assert.equal(events[0].payload.ctrlKey, false);
  assert.equal(events[0].payload.metaKey, true);
  assert.equal(events[0].payload.altKey, false);
  assert.equal(events[0].payload.shiftKey, false);
});

test('installDomWatcher: keydown with no modifiers held emits four falses', () => {
  const events = [];
  const handlers = {};
  const fakeRoot = {
    addEventListener: (t, h) => { handlers[t] = h; },
    removeEventListener: () => {},
  };
  const forward = (type, payload) => events.push({ type, payload });
  installDomWatcher(fakeRoot, forward, ['keydown']);
  const fakeInput = {
    getAttribute: (k) => k === 'placeholder' ? 'Search' : null,
    hasAttribute: () => false,
    tagName: 'INPUT',
    textContent: '',
    ownerDocument: null,
  };
  handlers.keydown({ target: fakeInput, key: 'a' });
  assert.equal(events.length, 1);
  assert.equal(events[0].payload.key, 'a');
  assert.equal(events[0].payload.ctrlKey, false);
  assert.equal(events[0].payload.metaKey, false);
  assert.equal(events[0].payload.altKey, false);
  assert.equal(events[0].payload.shiftKey, false);
});

test('createForwarder includes tabId in body when provided', async () => {
  const calls = [];
  const fakeFetch = async (url, opts) => { calls.push({ url, opts }); return { ok: true }; };
  const forward = createForwarder({
    endpoint: '/runbug/log',
    fetch: fakeFetch,
    guard: createGuard(),
    tabId: 'tab-abc-123',
  });
  await forward('log', ['hello']);
  const body = JSON.parse(calls[0].opts.body);
  assert.equal(body.tabId, 'tab-abc-123');
});

test('createForwarder omits tabId when not provided', async () => {
  const calls = [];
  const fakeFetch = async (url, opts) => { calls.push({ url, opts }); return { ok: true }; };
  const forward = createForwarder({
    endpoint: '/runbug/log',
    fetch: fakeFetch,
    guard: createGuard(),
  });
  await forward('log', ['hello']);
  const body = JSON.parse(calls[0].opts.body);
  assert.equal('tabId' in body, false);
});

import { shouldHandleEvent } from './shim.js';

test('shouldHandleEvent: absent targetTab returns true (broadcast)', () => {
  assert.equal(shouldHandleEvent({ type: 'configure' }, 'tab-abc'), true);
});

test('shouldHandleEvent: matching targetTab returns true', () => {
  assert.equal(shouldHandleEvent({ type: 'configure', targetTab: 'tab-abc' }, 'tab-abc'), true);
});

test('shouldHandleEvent: non-matching targetTab returns false', () => {
  assert.equal(shouldHandleEvent({ type: 'configure', targetTab: 'tab-other' }, 'tab-abc'), false);
});
