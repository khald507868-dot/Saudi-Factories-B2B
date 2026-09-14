// Offline checks for public catalogue pagination and independent strip loading.
// Run: node scripts/test_home_catalogue.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const read = file => fs.readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const html = read('index.html');
const start = html.indexOf('    /* Shared cards for the bestsellers strip');
const end = html.indexOf('\n  /* ============================================================', start);
assert(start > 0 && end > start);
const source = html.slice(start, end);

function fixture({ count = 57, failFirst = false, ratingsFail = false, authFail = false } = {}) {
  const nodes = {};
  for (const id of ['bestsellers-grid', 'all-products-grid', 'all-products-status', 'all-products-more']) {
    nodes[id] = {
      innerHTML: '', hidden: true, disabled: false, attrs: {}, events: {},
      querySelectorAll() { return []; },
      insertAdjacentHTML(_, html) { this.innerHTML += html; },
      setAttribute(key, value) { this.attrs[key] = value; },
      addEventListener(key, fn) { this.events[key] = fn; },
    };
  }
  const rows = Array.from({ length: count }, (_, i) => ({
    id: i + 1, factory_id: 8, name: 'Item <' + i + '>', price: '99',
    tiers: [{ min: 1, price: 32 }, { min: 10, price: 23 }],
    factories: { name: 'Factory', status: 'approved' }, images: [],
  }));
  let fail = failFirst;
  const ranges = [], mounts = [], requests = [];
  const context = vm.createContext({
    document: { documentElement: {}, getElementById: id => nodes[id], addEventListener() {} },
    localStorage: { getItem() { return null; }, setItem() {} },
    sfSafeHttpUrl: () => '', setInterval, clearInterval,
    SFBestsellersScroll: { mount(node) { mounts.push(node); } },
    SFReviews: { loadRatings(ids) {
      return ratingsFail ? Promise.reject(new Error('ratings unavailable'))
        : Promise.resolve(Object.fromEntries(ids.map(id => [id, { avg: 4.5, count: 2 }])));
    } },
    sb: { from(table) {
      assert.equal(table, 'products');
      const request = { orders: [] }; requests.push(request);
      return {
        select(value) { request.select = value; return this; },
        eq(key, value) { request.filter = [key, value]; return this; },
        order(key) { request.orders.push(key); return this; },
        limit(n) { return Promise.resolve({ data: rows.slice(0, n) }); },
        range(from, to) {
          ranges.push([from, to]);
          if (fail) { fail = false; return Promise.resolve({ error: { message: 'offline' } }); }
          return Promise.resolve({ data: rows.slice(from, to + 1) });
        },
      };
    } },
  });
  context.window = context;
  context.SF_AUTH_READY = authFail ? Promise.reject(new Error('auth unavailable')) : Promise.resolve();
  for (const file of ['currency.js', 'i18n.js', 'product-card-data.js']) vm.runInContext(read(file), context);
  vm.runInContext(source, context);
  return { nodes, ranges, mounts, requests, context, failNext() { fail = true; } };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
const ids = node => Array.from(node.innerHTML.matchAll(/data-fav="(\d+)"/g), m => Number(m[1]));

const f = fixture();
await settle();
const all = f.nodes['all-products-grid'], more = f.nodes['all-products-more'];
assert.equal(ids(all).length, 24);
assert.equal(ids(f.nodes['bestsellers-grid']).length, 24);
assert.deepEqual(f.mounts, [f.nodes['bestsellers-grid']]);
assert(all.innerHTML.includes('Item &lt;0&gt;'));
assert(all.innerHTML.includes(f.context.I18N.moneyRange('23', '32')));
assert(all.innerHTML.includes('4.5 (2)'));
assert.equal(more.hidden, false);
f.failNext();
await more.events.click();
assert.equal(ids(all).length, 24, 'failed next page preserves existing cards');
assert.equal(more.textContent, f.context.I18N.t('app_retry'));
await more.events.click();
assert.equal(ids(all).length, 48);
await more.events.click();
assert.deepEqual(ids(all), Array.from({ length: 57 }, (_, i) => i + 1));
assert.equal(more.hidden, true);
assert.equal(all.attrs['aria-busy'], 'false');
assert.deepEqual(f.ranges, [[0,24], [24,48], [24,48], [48,72]]);
for (const r of f.requests.filter(r => r.filter)) {
  assert.match(r.select, /factories!inner/);
  assert.deepEqual(r.filter, ['factories.status', 'approved']);
  assert.deepEqual(r.orders, ['sort_order', 'id']);
}

for (const count of [0, 24, 25]) {
  const x = fixture({ count }); await settle();
  assert.equal(ids(x.nodes['all-products-grid']).length, Math.min(24, count));
  assert.equal(x.nodes['all-products-more'].hidden, count <= 24);
  assert.equal(x.nodes['all-products-status'].hidden, count !== 0);
}
const unavailable = fixture({ failFirst: true }); await settle();
assert.equal(ids(unavailable.nodes['bestsellers-grid']).length, 24, 'catalogue failure does not hide bestsellers');
await unavailable.nodes['all-products-more'].events.click();
assert.equal(ids(unavailable.nodes['all-products-grid']).length, 24);
const noRatings = fixture({ ratingsFail: true }); await settle();
assert.equal(ids(noRatings.nodes['all-products-grid']).length, 24);
const noAuth = fixture({ authFail: true }); await settle();
assert.equal(ids(noAuth.nodes['all-products-grid']).length, 0);
assert.equal(noAuth.nodes['all-products-status'].textContent, noAuth.context.I18N.t('home_products_failed'));
console.log('PASS complete pagination, approved-only query, stable order, escaping, shared prices/ratings, empty states, independent loading, retry, and auth failure');
