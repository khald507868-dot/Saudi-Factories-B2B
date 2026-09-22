import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../site-search.js', import.meta.url), 'utf8');
class Element {
  constructor(tag = 'div') { this.tagName = tag.toUpperCase(); this.children = []; this.dataset = {}; this.attrs = {}; this.handlers = {}; this.textContent = ''; this.hidden = false; this.value = ''; }
  setAttribute(key, value) { this.attrs[key] = value; }
  appendChild(child) { if (child.parent) child.remove(); this.children.push(child); child.parent = this; return child; }
  insertBefore(child, before) { if (child.parent) child.remove(); this.children.splice(this.children.indexOf(before), 0, child); child.parent = this; }
  remove() { this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; }
  replaceWith(other) { const parent = this.parent; const index = parent.children.indexOf(this); this.remove(); parent.children.splice(index, 0, other); other.parent = parent; }
  get firstChild() { return this.children[0]; }
  addEventListener(name, handler) { this.handlers[name] = handler; }
  querySelector(selector) {
    const match = element => selector === 'button[type="submit"]' ? element.tagName === 'BUTTON' && element.type === 'submit' : element.tagName.toLowerCase() === selector;
    for (const child of this.children) { if (match(child)) return child; const found = child.querySelector(selector); if (found) return found; }
    return null;
  }
  replaceChildren(...children) { this.children.forEach(child => { child.parent = null; }); this.children = []; children.forEach(child => this.appendChild(child)); }
  contains(target) { return this === target || this.children.some(child => child.contains(target)); }
  querySelectorAll(selector) { return this.children.flatMap(child => [...(child.tagName.toLowerCase() === selector ? [child] : []), ...child.querySelectorAll(selector)]); }
  focus() { this.focused = true; }
  reportValidity() { this.validityReported = true; }
}
function setup(client, query = '', resultPage = false) {
  const container = new Element(); const box = new Element(); box.className = 'search-box'; container.appendChild(box);
  box.appendChild(new Element('svg')); const input = box.appendChild(new Element('input'));
  const ids = new Map();
  if (resultPage) for (const id of ['catalog-search-results', 'catalog-search-term', 'catalog-search-prompt', ...['products','factories'].flatMap(k => ['catalog-' + k, 'catalog-' + k + '-status', 'catalog-' + k + '-more'])]) ids.set(id, new Element());
  const document = { readyState: 'loading', createElement: tag => new Element(tag), getElementById: id => ids.get(id),
    querySelectorAll: () => container.children, querySelector: () => input, addEventListener(name, fn) { if (name === 'DOMContentLoaded') this.start = fn; } };
  const navigations = [];
  const window = { sb: client, location: { search: query, assign: url => navigations.push(url) }, I18N: { t: key => key }, SF_AUTH_READY: Promise.resolve(),
    sfSafeHttpUrl(raw) { try { const url = new URL(raw); return ['https:', 'http:'].includes(url.protocol) ? url.href : ''; } catch { return ''; } } };
  vm.runInNewContext(source, { window, document, URLSearchParams, encodeURIComponent, Promise, setTimeout, clearTimeout });
  return { window, document, ids, container, input, navigations, api: window.SFSiteSearch };
}
function clientWith(reply) {
  const calls = [];
  return { calls, from(table) {
    const call = { table, filters: [], orders: [] }; calls.push(call);
    const query = { select(fields) { call.fields = fields; return query; }, eq(...args) { call.filters.push(args); return query; },
      or(filter) { call.or = filter; return query; }, ilike(...args) { call.match = args; return query; }, order(column) { call.orders.push(column); return query; },
      range(...args) { call.range = args; return Promise.resolve(reply(call, calls)); } };
    return query;
  } };
}
const client = clientWith(() => ({ data: Array.from({ length: 21 }, (_, id) => ({ id })) }));
const { api } = setup(client);
assert.equal(api.normalize('  قطع   غيار  '), 'قطع غيار');
assert.equal(api.normalize('***'), '');
assert.equal(api.normalize('a'.repeat(500)).length, 120);
const page = await api.fetchPage(client, 'products', ' Car ', 0);
assert.equal(page.rows.length, 20); assert.equal(page.more, true);
assert.deepEqual(client.calls[0].filters, [['factories.status','approved']]);
assert(client.calls[0].fields.includes('factories!inner'));
assert.deepEqual(client.calls[0].match, ['name','%Car%']);
assert.deepEqual(client.calls[0].orders, ['name','id']); assert.deepEqual(client.calls[0].range, [0,20]);
await api.fetchPage(client, 'factories', '10%_\\ مصنع', 20);
assert.deepEqual(client.calls[1].filters, [['status','approved']]);
assert.deepEqual(client.calls[1].match, ['name','%10\\%\\_\\\\ مصنع%']);
assert.deepEqual(client.calls[1].range, [20,40]);
await api.fetchPage(client, 'factories', 'x),status.neq.approved', 0);
assert.deepEqual(client.calls[2].match, ['name','%x),status.neq.approved%']);
assert.deepEqual(client.calls[2].filters, [['status','approved']]);
const count = client.calls.length;
assert.equal((await api.fetchPage(client, 'products', '  ', 0)).rows.length, 0); assert.equal(client.calls.length, count);
await assert.rejects(() => api.fetchPage(clientWith(() => ({ error: { message:'denied' } })), 'products','car',0), /unavailable/);
console.log('PASS server-side name filtering, approved catalogue only, literal wildcard escaping, bounded queries and stable pagination');

const header = setup(client);
header.api.bind(); header.api.bind();
const form = header.container.firstChild;
assert.equal(form.tagName, 'FORM'); assert.equal(form.children.length, 3); assert.equal(form.attrs.role, 'search');
assert.equal(form.querySelector('button[type="submit"]').attrs['aria-label'], 'catalog_search_action');
header.input.value = 'سيارة & car'; let prevented = false;
form.handlers.submit({ preventDefault() { prevented = true; } });
assert(prevented); assert.equal(header.navigations[0], 'web-search.html?q=' + encodeURIComponent('سيارة & car'));
header.input.value = '  '; form.handlers.submit({ preventDefault() {} });
assert.equal(header.navigations.length, 1); assert(header.input.focused && header.input.validityReported);
console.log('PASS native Enter/button submit, accessible button, preserved input, encoded navigation and empty-input prevention');

let failProducts = true;
const responseClient = clientWith(call => call.table === 'products' && failProducts ? { error: {} } : {
  data: call.table === 'products' ? [{ id: '2&next=evil', name:'<img src=x onerror=alert(1)>', image:'javascript:alert(1)', factories:{ name:'<script>bad</script>' } }] : []
});
const ui = setup(responseClient, '?q=' + encodeURIComponent('<svg onload=alert(1)>'), true);
ui.document.start();
await new Promise(resolve => setImmediate(resolve));
assert.equal(ui.ids.get('catalog-search-term').textContent, '«<svg onload=alert(1)>»');
assert.equal(ui.ids.get('catalog-products-status').textContent, 'catalog_search_failed');
assert.equal(ui.ids.get('catalog-products-more').textContent, 'app_retry');
assert.equal(ui.ids.get('catalog-factories-status').textContent, 'no_results');
failProducts = false;
await ui.ids.get('catalog-products-more').handlers.click();
assert.deepEqual(responseClient.calls.filter(c => c.table === 'products').map(c => c.range), [[0,20],[0,20]]);
const resultCard = ui.ids.get('catalog-products').firstChild;
assert.equal(resultCard.href, 'web-product.html?id=2%26next%3Devil');
assert.equal(resultCard.querySelector('h3').textContent, '<img src=x onerror=alert(1)>');
assert.equal(resultCard.querySelector('img'), null);
assert.equal(ui.ids.get('catalog-products-more').hidden, true);
assert.equal(ui.ids.get('catalog-products').attrs['aria-busy'], 'false');
const emptyClient = clientWith(() => { throw Error('Empty query must not fetch'); });
const empty = setup(emptyClient, '?q=%20', true); empty.document.start();
assert.equal(empty.ids.get('catalog-search-results').hidden, true); assert.equal(emptyClient.calls.length, 0);
console.log('PASS independent results/errors, retry without skipping rows, safe text/URLs, no-results and blank search states');

for (const page of ['index.html','web-factories.html','web-factory.html','web-product.html']) {
  const html = fs.readFileSync(new URL('../'+page, import.meta.url),'utf8');
  assert(html.includes('site-search.js?v=20260922-live-search'));
  assert(html.includes('site-search.css?v=20260922-live-search'));
}
assert(fs.readFileSync(new URL('../top-bar.js',import.meta.url),'utf8').indexOf('global.SFSiteSearch.bind()') < fs.readFileSync(new URL('../top-bar.js',import.meta.url),'utf8').indexOf('if (!injected) return;'));
console.log('PASS search is wired in both the existing home header and injected catalogue headers');

assert(api.score('سيارة كهربائية', 'سياره') > 0);
assert(api.score('أثاث مكتبي', 'اثاث') > 0);
assert(api.score('Phone', 'phnoe') > 0);
assert(api.score('Cars', 'car') > api.score('Cat', 'car'));
assert.equal(api.score('Office chair', 'phone'), 0);
assert.equal(api.score('Office chair', 'office phone'), 0);
const fuzzyClient = clientWith(call => ({ data: call.or ? [
  { id: 1, name: 'Phone' }, { id: 2, name: 'Office chair' }, { id: 3, name: 'Phones' }
] : [] }));
const fuzzy = await api.suggestions(fuzzyClient, 'products', 'phnoe');
assert.equal(fuzzy[0].name, 'Phone'); assert(!fuzzy.some(row => row.name === 'Office chair'));
assert(fuzzyClient.calls.every(call => call.filters[0][0] === 'factories.status' && call.filters[0][1] === 'approved'));
assert.deepEqual(fuzzyClient.calls[1].range, [0,119]);
assert(fuzzyClient.calls[1].or.includes('name.ilike."%ph%"'));
const fallback = await api.fetchPage(fuzzyClient, 'products', 'phnoe', 0);
assert(fallback.similar && fallback.rows.length > 0);
console.log('PASS Arabic spelling normalization, partial matches, simple typos, relevance ordering and bounded public candidate queries');

const pause = () => new Promise(resolve => setTimeout(resolve, 330));
const typeClient = clientWith(call => ({ data: call.table === 'products' ? [{ id: 4, name: 'Car', price: null }] : [] }));
const typing = setup(typeClient); typing.api.bind();
const popup = typing.container.firstChild.children.at(-1);
typing.input.value = 'c'; typing.input.handlers.input();
typing.input.value = 'ca'; typing.input.handlers.input();
typing.input.value = 'car'; typing.input.handlers.input();
assert.equal(popup.hidden, false); assert.equal(typing.input.attrs['aria-expanded'], 'true');
await pause();
assert(typeClient.calls.filter(call => call.match).every(call => call.match[1] === '%car%'));
assert.equal(popup.querySelector('a').href, 'web-product.html?id=4');
typing.input.value = ''; typing.input.handlers.input();
assert.equal(popup.hidden, true); assert.equal(typing.input.attrs['aria-expanded'], 'false');

const oldResponses = [];
const raceClient = clientWith(call => {
  if (call.match && call.match[1] === '%old%') return new Promise(resolve => oldResponses.push(resolve));
  return { data: call.table === 'products' && call.match ? [{ id: 9, name: 'New phone' }] : [] };
});
const race = setup(raceClient); race.api.bind();
race.input.value = 'old'; race.input.handlers.input(); await pause();
race.input.value = 'new'; race.input.handlers.input(); await pause();
const racePopup = race.container.firstChild.children.at(-1);
assert.equal(racePopup.querySelector('a').href, 'web-product.html?id=9');
oldResponses.forEach(resolve => resolve({ data: [{ id: 2, name: 'Old phone' }] }));
await new Promise(resolve => setImmediate(resolve));
assert.equal(racePopup.querySelector('a').href, 'web-product.html?id=9');
race.container.firstChild.handlers.keydown({ key:'Escape', preventDefault() {} });
assert.equal(racePopup.hidden, true);
console.log('PASS live results without Enter, debounce, clearing, Escape and stale-response suppression');
