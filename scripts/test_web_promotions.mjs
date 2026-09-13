// Offline service checks. Server RLS is covered by test_home_promotions.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const uid = '10000000-0000-4000-8000-000000000001';
const image = 'https://project.example/storage/v1/object/public/promotion-media/' + uid + '/promotions/banner.png';
let calls = [], records = [], resultError = null, uploads = 0;
const context = vm.createContext({ URL, I18N: { t: key => key },
  SUPABASE_URL: 'https://project.example', SF_AUTH_READY: Promise.resolve(),
  SF_USER: null, SF_PROFILE: null,
  SFUpload: { async uploadFile() { uploads++; return { url: image, path: uid + '/promotions/banner.png' }; } },
});
context.window = context;
context.sb = {
  from(table) {
    const operation = { table, filters: [] };
    calls.push(operation);
    const query = {
      select() { return this; },
      eq(key, value) { operation.filters.push([key, value]); return this; },
      order() { return this; }, limit() { return this; },
      insert(values) { operation.kind = 'insert'; operation.values = values; return this; },
      update(values) { operation.kind = 'update'; operation.values = values; return this; },
      delete() { operation.kind = 'delete'; return this; },
      async single() {
        return { error: resultError, data: resultError ? null : { id: 'saved', ...operation.values } };
      },
      then(resolve, reject) {
        const rows = records.filter(row => operation.filters.every(([key, value]) => row[key] === value));
        return Promise.resolve({ error: resultError, data: rows }).then(resolve, reject);
      },
    };
    return query;
  },
  storage: { from: bucket => ({ remove: async paths => { calls.push({ bucket, paths }); return {}; } }) },
};
vm.runInContext(readFileSync(new URL('../promotions-service.js', import.meta.url), 'utf8'), context);
const service = context.SFPromotions;
const file = { type: 'image/png', size: 1024 };
const values = { title: 'Offer', image_url: image, target_url: 'https://example.com/offer', sort_order: 0, is_active: true };

for (const user of [null, { id: uid }]) {
  context.SF_USER = user;
  context.SF_PROFILE = { is_admin: false };
  calls = [];
  await assert.rejects(service.listAdmin(), /promo_admin_only/);
  await assert.rejects(service.save(values, file), /promo_admin_only/);
  await assert.rejects(service.remove({ id: 'saved' }), /promo_admin_only/);
  assert.equal(calls.length, 0);
  assert.equal(uploads, 0);
}
records = [{ id: 'active', is_active: true }, { id: 'hidden', is_active: false }];
assert.equal((await service.listPublic()).length, 1);
context.SF_USER = { id: uid };
context.SF_PROFILE = { is_admin: true };
assert.equal((await service.listAdmin()).length, 2);
for (const url of ['javascript:alert(1)', 'http://example.com', 'https://name:pass@example.com']) {
  await assert.rejects(service.save({ ...values, target_url: url }, file), /promo_target_invalid/);
}
await assert.rejects(service.save({ ...values, title: ' ' }, file), /promo_title_required/);
await assert.rejects(service.save({ ...values, sort_order: -1 }, file), /promo_order_invalid/);
await assert.rejects(service.save(values, { type: 'image/svg+xml', size: 1024 }), /promo_image_invalid/);
await assert.rejects(service.save(values, { type: 'image/png', size: 5242881 }), /promo_image_invalid/);
await assert.rejects(service.save({ ...values, image_url: 'https://outside.example/banner.png' }), /promo_image_required/);
assert.equal(uploads, 0);
assert.equal(service.imagePath(image), uid + '/promotions/banner.png');
assert.equal(service.imagePath(image + '?other=1'), null);
assert.equal(service.imagePath(image.replace('project.example', 'outside.example')), null);
assert.equal((await service.save(values, file)).title, 'Offer');
assert.equal(uploads, 1);
assert.equal((await service.save({ ...values, id: 'saved', is_active: false })).is_active, false);
resultError = new Error('Server denied write');
await assert.rejects(service.save(values), /Server denied write/);
await assert.rejects(service.remove({ id: 'saved' }), /Server denied write/);
resultError = null;
records = [];
calls = [];
await service.remove({ id: 'saved', image_url: image });
assert.equal(calls.some(call => call.bucket === 'promotion-media'), true);
console.log('PASS admin-only writes/uploads, active-only public listing, validation, save/edit/delete, and server error handling');
