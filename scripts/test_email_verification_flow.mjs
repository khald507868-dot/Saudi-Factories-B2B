// Offline regression: an existing confirmed account must not wait for signup OTP.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const settle = () => new Promise(resolve => setImmediate(resolve));

function fixture({ confirmed = true, signedIn = true, factoryStatus = 'rejected', error = false } = {}) {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      value: '', textContent: '', disabled: false,
      classList: { toggle() {} },
      listeners: {}, reportValidity: () => true,
      addEventListener(event, fn) { this.listeners[event] = fn; },
    });
    return elements.get(id);
  }
  const calls = { resend: 0, verify: 0, paths: [] };
  const user = { id: 'owner', email: 'owner@example.test', email_confirmed_at: confirmed ? '2026-09-13' : null };
  const context = {
    Date, setInterval() {},
    I18N: { t: key => key, applyTranslations() {} },
    sessionStorage: { getItem: key => key === 'sf_verification_email' ? user.email : null },
    location: { replace: path => calls.paths.push(path) },
    document: {
      body: { dataset: { accountGate: 'verify' } },
      getElementById: element,
      querySelectorAll: () => [...elements.values()],
    },
    sb: {
      auth: {
        getSession: async () => ({ data: { session: signedIn ? { user } : null }, error: error ? new Error('offline') : null }),
        getUser: async () => ({ data: { user } }),
        resend: async () => { calls.resend++; return {}; },
        verifyOtp: async () => { calls.verify++; return { error: new Error('invalid OTP') }; },
      },
      from(table) {
        return {
          select() { return this; }, eq() { return this; }, order() { return this; }, limit() { return this; },
          single: async () => ({ data: { account_type: 'factory', is_admin: false } }),
          maybeSingle: async () => ({ data: { status: factoryStatus, rejection_reason: 'Missing document' } }),
        };
      },
    },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(read('account-access.js'), context);
  vm.runInContext(read('account-gate.js'), context);
  return { calls, element, async click(id) { await element(id).listeners.click.call(element(id)); } };
}

for (const factoryStatus of ['pending', 'rejected', 'approved']) {
  const f = fixture({ factoryStatus });
  await settle();
  assert.equal(f.calls.paths[0], factoryStatus === 'approved' ? 'index.html' : 'web-account-pending.html');
  await f.click('resend-code');
  assert.equal(f.calls.resend, 0, 'Confirmed accounts do not request signup emails');
}

const unconfirmed = fixture({ confirmed: false });
await settle();
assert.equal(unconfirmed.calls.paths.length, 0);
await unconfirmed.click('resend-code');
assert.equal(unconfirmed.calls.resend, 1);
assert.equal(unconfirmed.element('gate-status').textContent, 'auth_resend_requested');
await unconfirmed.click('resend-code');
assert.equal(unconfirmed.calls.resend, 1, 'Cooldown prevents repeated resend');
await unconfirmed.element('verification-form').listeners.submit.call(unconfirmed.element('verification-form'), { preventDefault() {} });
assert.equal(unconfirmed.calls.verify, 1);
assert.equal(unconfirmed.element('gate-status').textContent, 'auth_code_failed');
assert.equal(unconfirmed.calls.paths.length, 0, 'Invalid code never grants access');

const signedOut = fixture({ signedIn: false });
await settle();
await signedOut.click('resend-code');
assert.equal(signedOut.calls.resend, 1);
assert.equal(signedOut.element('gate-status').textContent, 'auth_resend_requested');
assert.equal(signedOut.calls.paths.length, 0);

const offline = fixture({ error: true });
await settle();
assert.equal(offline.element('gate-status').textContent, 'auth_check_failed');
await offline.click('resend-code');
assert.equal(offline.calls.resend, 0);
assert.equal(offline.element('gate-status').textContent, 'auth_resend_failed');
console.log('PASS confirmed/rejected/pending routing, no repeat signup email, unconfirmed resend, cooldown, invalid OTP and network failure');
