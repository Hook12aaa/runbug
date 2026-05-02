// Runbug reference shim — dev-only, vanilla JS, zero runtime deps.
// Claude lifts + adapts this into target projects per install-bridge instructions.
// Integrity constraints I1/I2/I3 enforced below.

export function createGuard() {
  let active = false;
  return {
    enter() {
      if (active) return false;
      active = true;
      return true;
    },
    exit() {
      active = false;
    },
  };
}

export function createForwarder({ endpoint, fetch: fetchImpl, guard, tabId }) {
  return async function forward(level, args) {
    if (!guard.enter()) return;
    try {
      const body = JSON.stringify({
        type: 'console',
        ts: new Date().toISOString(),
        ...(tabId ? { tabId } : {}),
        level,
        args,
      });
      await fetchImpl(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/ndjson' },
        body,
      });
    } catch {
      // I2: swallow — never console.* from this path.
    } finally {
      guard.exit();
    }
  };
}

// I3: address validation — exactly {role, accessibleName, nth?}.
const AX_ALLOWED = new Set(['role', 'accessibleName', 'nth']);

export function validateAxAddress(addr) {
  if (!addr || typeof addr !== 'object' || Array.isArray(addr)) {
    throw new Error('address must be an object');
  }
  for (const key of Object.keys(addr)) {
    if (!AX_ALLOWED.has(key)) {
      throw new Error(
        `address key "${key}" is not allowed — use {role, accessibleName, nth}`,
      );
    }
  }
  if (typeof addr.role !== 'string' || addr.role.length === 0) {
    throw new Error('address.role is required and must be a non-empty string');
  }
  if (typeof addr.accessibleName !== 'string' || addr.accessibleName.length === 0) {
    throw new Error('address.accessibleName is required and must be a non-empty string');
  }
  if ('nth' in addr && (!Number.isInteger(addr.nth) || addr.nth < 0)) {
    throw new Error('address.nth must be a non-negative integer');
  }
  return true;
}

// DOM-dependent — integration tested via verify-bridge.sh in the target project.

export function resolveAx(address, root) {
  validateAxAddress(address);
  const doc = root || (typeof document !== 'undefined' ? document : null);
  if (!doc) throw new Error('resolveAx requires a DOM root');
  const matches = [];
  const walker = doc.createTreeWalker(doc, 1 /* NodeFilter.SHOW_ELEMENT */);
  let node = walker.currentNode;
  while (node) {
    if (computeRole(node) === address.role && computeAccessibleName(node) === address.accessibleName) {
      matches.push(node);
    }
    node = walker.nextNode();
  }
  if (matches.length === 0) {
    const err = new Error(`no match for ${JSON.stringify(address)}`);
    err.code = 'no-match';
    throw err;
  }
  if (matches.length > 1 && address.nth === undefined) {
    const err = new Error(`${matches.length} matches — pass nth to disambiguate`);
    err.code = 'multiple-matches-need-nth';
    throw err;
  }
  return matches[address.nth || 0];
}

export async function dispatchAction(action, root) {
  const el = resolveAx(action.target, root);
  try {
    if (action.action === 'click') {
      el.click();
    } else if (action.action === 'input') {
      const proto = Object.getPrototypeOf(el);
      const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
      if (setter) setter.call(el, action.value);
      else el.value = action.value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    } else if (action.action === 'keypress') {
      el.dispatchEvent(new KeyboardEvent('keydown', { key: action.value, bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keyup', { key: action.value, bubbles: true }));
    } else if (action.action === 'focus') {
      el.focus();
    } else if (action.action === 'blur') {
      el.blur();
    } else {
      const err = new Error(`unknown action: ${action.action}`);
      err.code = 'action-threw';
      throw err;
    }
    return { id: action.id, ok: true, resolvedRole: computeRole(el), resolvedAccessibleName: computeAccessibleName(el) };
  } catch (e) {
    return { id: action.id, ok: false, error: e.code || 'action-threw' };
  }
}

export function installConsoleProxy({ forward, consoleObj }) {
  const c = consoleObj || (typeof console !== 'undefined' ? console : null);
  if (!c) throw new Error('installConsoleProxy requires a console object');
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    const original = c[level].bind(c);
    c[level] = (...args) => {
      forward(level, args);
      original(...args);
    };
  }
}

// Not full ANDC. Coverage against target app is install-bridge's Bottom Line responsibility.

function computeRole(el) {
  const explicit = el.getAttribute && el.getAttribute('role');
  if (explicit) return explicit;
  const tag = el.tagName && el.tagName.toLowerCase();
  const implicitRoles = {
    button: 'button',
    a: el.hasAttribute && el.hasAttribute('href') ? 'link' : null,
    input: (() => {
      const t = (el.getAttribute && el.getAttribute('type')) || 'text';
      if (t === 'checkbox') return 'checkbox';
      if (t === 'radio') return 'radio';
      if (t === 'range') return 'slider';
      if (t === 'submit' || t === 'button' || t === 'reset') return 'button';
      return 'textbox';
    })(),
    textarea: 'textbox',
    select: 'combobox',
    nav: 'navigation',
    main: 'main',
    header: 'banner',
    footer: 'contentinfo',
    h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading',
  };
  return implicitRoles[tag] || null;
}

function computeAccessibleName(el) {
  if (!el.getAttribute) return '';
  const ariaLabel = el.getAttribute('aria-label');
  if (ariaLabel) return ariaLabel.trim();
  const labelledBy = el.getAttribute('aria-labelledby');
  if (labelledBy && el.ownerDocument) {
    const refs = labelledBy.split(/\s+/).map((id) => el.ownerDocument.getElementById(id)).filter(Boolean);
    if (refs.length) return refs.map((r) => (r.textContent || '').trim()).join(' ');
  }
  if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
    const id = el.getAttribute('id');
    if (id && el.ownerDocument) {
      const label = el.ownerDocument.querySelector(`label[for="${id}"]`);
      if (label) return (label.textContent || '').trim();
    }
    let parent = el.parentElement;
    while (parent) {
      if (parent.tagName === 'LABEL') return (parent.textContent || '').trim();
      parent = parent.parentElement;
    }
    const placeholder = el.getAttribute('placeholder');
    if (placeholder) return placeholder.trim();
  }
  return (el.textContent || '').trim();
}

export function emitShimReady(forward, url, version) {
  if (typeof url !== 'string' || url.length === 0) {
    throw new Error('emitShimReady: url is required');
  }
  if (typeof version !== 'string' || version.length === 0) {
    throw new Error('emitShimReady: version is required');
  }
  forward('shim-ready', { url, shimVersion: version });
}

export function configureFromEvent(event, shim, forward) {
  if (!('watch_dom' in event)) return;
  const val = event.watch_dom;
  if (Array.isArray(val)) {
    shim.setDomWatcherEvents(val);
  }
}

export function installDomWatcher(root, forward, allowedEvents) {
  const events = allowedEvents || ['click', 'submit'];
  const TEXT_INPUT_ROLES = new Set(['textbox', 'searchbox', 'combobox']);
  const handlers = events.map((eventType) => {
    const handler = (e) => {
      const target = e.target;
      if (!target || typeof target !== 'object') return;
      const role = computeRole(target);
      if (!role) return;
      const accessibleName = computeAccessibleName(target);
      if (!accessibleName) return;
      const payload = { eventType, target: { role, accessibleName } };
      if (eventType === 'input' && TEXT_INPUT_ROLES.has(role) && typeof target.value === 'string') {
        payload.value = target.value;
      }
      if (eventType === 'keydown') {
        payload.key = typeof e.key === 'string' ? e.key : '';
        payload.ctrlKey = !!e.ctrlKey;
        payload.metaKey = !!e.metaKey;
        payload.altKey = !!e.altKey;
        payload.shiftKey = !!e.shiftKey;
      }
      forward('dom-event', payload);
    };
    root.addEventListener(eventType, handler, true);
    return { eventType, handler };
  });
  return function detach() {
    for (const { eventType, handler } of handlers) {
      root.removeEventListener(eventType, handler, true);
    }
  };
}

export function shouldHandleEvent(event, tabId) {
  return !event.targetTab || event.targetTab === tabId;
}
