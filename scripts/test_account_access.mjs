import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../account-access.js', import.meta.url), 'utf8');
let user, profile, factory, failure, autoConfirm, calls, target;
const ctx = { I18N: { t: k => k }, SUPABASE_URL: 'https://example.test', SUPABASE_KEY: 'public',
  sessionStorage: { setItem() {} }, location: { replace: x => { target = x; } },
  fetch: async () => ({ ok: true, json: async () => ({ mailer_autoconfirm: autoConfirm }) }),
  sb: { auth: {
    getUser: async () => ({ data: { user }, error: failure }),
    signOut: async () => { calls.push('signOut'); return {}; },
    signUp: async () => { calls.push('signUp'); return { data: { user, session: null } }; },
  }, from(table) {
    const q = { select() { return this; }, eq() { return this; }, order() { return this; }, limit() { return this; },
      single: async () => ({ data: profile, error: failure }),
      maybeSingle: async () => ({ data: factory, error: failure }) };
    assert.ok(['profiles', 'factories'].includes(table)); return q;
  } },
};
ctx.window = ctx; vm.runInNewContext(source, ctx);
const api = ctx.SFAccountAccess;
user = { id: 'owner', email: 'owner@example.test', email_confirmed_at: null };
profile = { account_type: 'factory', is_admin: false }; factory = { status: 'pending' };
assert.equal((await api.check()).state, 'email_required');
await api.finish('index.html'); assert.equal(target, 'web-verify-email.html');
user.email_confirmed_at = '2026-09-13';
for (const state of ['pending', 'rejected']) {
  factory.status = state;
  assert.equal((await api.check()).state, state);
  await api.finish('web-factory.html'); assert.equal(target, 'web-account-pending.html');
}
factory = null; assert.equal((await api.check()).state, 'pending');
factory = { status: 'approved' }; await api.finish('web-factory.html'); assert.equal(target, 'web-factory.html');
profile.is_admin = true; factory.status = 'pending'; assert.equal((await api.check()).state, 'ready');
profile = { account_type: 'individual' }; assert.equal((await api.check()).state, 'ready');
profile = null; await assert.rejects(api.check);
failure = new Error('offline'); await assert.rejects(api.check); failure = null;
autoConfirm = true; calls = []; await assert.rejects(() => api.signUp({})); assert.equal(calls.length, 0);
autoConfirm = false; await api.signUp({}); assert.deepEqual(calls, ['signOut', 'signUp']);
user.identities = [];
await assert.rejects(() => api.signUp({}), /auth_existing_account/);
user.identities = [{ id: 'email-identity' }];
assert.ok((await api.signUp({})).data.user);
console.log('PASS email gate, pending/rejected/missing/approved factories, administrator, failure closed, confirmation configuration, previous session cleared');

// Every guarded HTML entry loads the gate before auth-guard, and both signup
// pages route to code entry even if old client behavior would have redirected.
for (const file of ['web-login.html', 'web-supplier.html']) {
  const html = readFileSync(new URL('../' + file, import.meta.url), 'utf8');
  assert.ok(html.includes('SFAccountAccess.signUp('));
  assert.ok(html.includes('SFAccountAccess.verifyEmail(emailInput.value.trim()'));
  assert.ok(html.includes('SFAccountAccess.finish(sfAuthReturnTarget('));
  for (const match of html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);
}
console.log('PASS individual and factory signup/login integration and inline script syntax');
