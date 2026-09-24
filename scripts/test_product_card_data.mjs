// Offline regression checks: shared pricing and similar-card data loading.
// Run: node scripts/test_product_card_data.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = name => readFileSync(new URL('../' + name, import.meta.url), 'utf8');
const context = vm.createContext({
  document: { documentElement: {}, addEventListener() {} },
  localStorage: { getItem() { return null; }, setItem() {} },
  escapeHTML: value => String(value).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]),
  sfSafeHttpUrl: value => /^https?:\/\//.test(value || '') ? value : '',
  imageIcon: '<svg></svg>',
  checkIcon: '<svg></svg>',
});
context.window = context;
for (const file of ['currency.js', 'i18n.js', 'product-card-data.js']) {
  vm.runInContext(read(file), context, { filename: file });
}
const { I18N, SFCurrency, SFProductCard } = context;
const product = {
  id: 7, factory_id: 8, name: 'Product <name>', price: '99',
  tiers: [{ min: 1, price: 32 }, { min: 10, price: 23 }],
  factories: { name: 'Factory <supplier>', status: 'approved' },
};
assert.equal(SFProductCard.priceHTML(product), I18N.moneyRange('23', '32'));
assert.equal(SFProductCard.priceHTML({ ...product, tiers: [] }), I18N.money('99'));
assert.equal(SFProductCard.priceHTML({ ...product, tiers: [{ min: 1, price: 23.5 }] }), I18N.money('23.50'));
assert.equal(SFProductCard.priceHTML({ ...product, tiers: [null, { min: 0, price: 1 }, { min: 1, price: -3 }, { min: 1, price: 'Infinity' }] }), I18N.money('99'));
assert.equal(SFProductCard.priceHTML({ price: null }), '');
SFCurrency.setCode('USD');
assert.equal(SFProductCard.priceHTML(product), I18N.moneyRange('23', '32'));
assert.match(SFProductCard.priceHTML(product), /cur-sym/);
SFCurrency.setCode('SAR');

const source = read('web-product.html');
vm.runInContext(source.slice(source.indexOf('      var STAR_PATH ='), source.indexOf('      function rvDate(')), context);
vm.runInContext(source.slice(source.indexOf('      function similarCardHTML('), source.indexOf('      function startSimilarLoop(')), context);
vm.runInContext(source.slice(source.indexOf('      function loadSimilar('), source.indexOf('\n      if (window.sb) {', source.indexOf('      function loadSimilar('))), context);
let card = context.similarCardHTML(product, { avg: 4.3, count: 12 });
assert.ok(card.includes(I18N.moneyRange('23', '32')));
assert.match(card, /4\.3 \(12\)/);
assert.match(card, /clip-path:inset\(0 70\.00% 0 0\)/);
assert.match(card, /similar-verified/);
assert.match(card, /data-sf-translate>Product &lt;name&gt;/);
assert.match(card, /pc-factory-name">Factory &lt;supplier&gt;/);
assert(card.indexOf('class="similar-rating"') < card.indexOf('class="similar-price"'));
assert.match(card, /<article class="similar-card" data-product-id="7"><a class="similar-link"/);
assert.match(card, /<\/a><div class="pc-pricing">/);
assert.match(card, /<bdi>1–9<\/bdi>/);
assert.match(card, /<tr data-pc-extra hidden>/);
assert.match(card, /class="pc-pricing-toggle" aria-expanded="false"/);
assert.doesNotMatch(context.similarCardHTML({...product,tiers:[]}), /pc-pricing-toggle/);
for (const status of ['pending', 'rejected', undefined]) {
  card = context.similarCardHTML({ ...product, factories: { status } });
  assert.doesNotMatch(card, /similar-verified/);
  assert.match(card, /similar-rating-empty/);
}
const unrated=context.similarCardHTML(product, { avg: 0, count: 0 });
assert.match(unrated, /similar-rating-empty/);
assert.doesNotMatch(unrated, /0\.0 \/ 5|0\.0 \(0\)/);
assert(unrated.includes(I18N.t('reviews_none')));

vm.runInContext(source.slice(source.indexOf('      function startSimilarLoop('),source.indexOf('      function loadSimilar(')),context);
const mounts=[];
context.SFBestsellersScroll={mount(node,options){mounts.push({node,options});}};
const handlers=[],cards=[];
const interactiveTrack={addEventListener(name,fn){assert.equal(name,'click');handlers.push(fn);},querySelectorAll(){return cards;}};
context.startSimilarLoop(interactiveTrack);context.startSimilarLoop(interactiveTrack);
assert.equal(handlers.length,1,'Repeated loads do not duplicate toggle handlers');
assert.equal(mounts[0].options.itemSelector,'.similar-card');
assert.equal(mounts[0].options.sectionSelector,'.similar-strip');
assert.equal(mounts[0].options.repeatToFill,true);
assert.equal(mounts[0].options.pauseOnHover,false);
assert.equal(mounts[0].options.pauseOnPointerFocus,false);
function control(id){
 const rows=[{hidden:true},{hidden:true}];
 const btn={attrs:{'aria-expanded':'false'},getAttribute(k){return this.attrs[k];},setAttribute(k,v){this.attrs[k]=v;},closest(){return item;}};
 const item={getAttribute(){return id;},querySelectorAll(){return rows;},querySelector(){return btn;}};
 return {item,btn,rows};
}
const original=control('7'),copy=control('7'),other=control('8');cards.push(original.item,copy.item,other.item);
let prevented=0;
const event={target:{closest(){return copy.btn;}},preventDefault(){prevented++;}};
handlers[0](event);
assert.equal(prevented,1);assert(original.rows.every(row=>!row.hidden));assert(copy.rows.every(row=>!row.hidden));assert(other.rows.every(row=>row.hidden));
assert.equal(original.btn.attrs['aria-expanded'],'true');
handlers[0](event);assert(original.rows.every(row=>row.hidden));assert(copy.rows.every(row=>row.hidden));

const box = { hidden: true }, track = { innerHTML: '' };
context.document.getElementById = id => id === 'similar-strip' ? box : track;
const events = [];
context.startSimilarLoop = () => events.push('loop');
context.SFTranslate = { translateAll: target => { assert.equal(target, track); events.push('translate'); } };
const query = {
  select(fields) { assert.match(fields, /tiers/); assert.match(fields, /\bmoq\b/); assert.match(fields, /factories\(name,status\)/); return this; },
  eq(field, id) { assert.equal(field, 'factory_id'); assert.equal(id, 8); return this; },
  order() { return this; }, limit() { return this; },
  then(resolve) { return Promise.resolve({ data: [product, { ...product, id: 9 }] }).then(resolve); },
};
context.sb = { from: table => { assert.equal(table, 'products'); return query; } };
context.SFReviews = { loadRatings: ids => {
  assert.deepEqual(Array.from(ids), [7]);
  return Promise.resolve({ 7: { avg: 4.3, count: 12 } });
} };
await context.loadSimilar(8, 9);
assert.equal(box.hidden, false);
assert.match(track.innerHTML, /4\.3 \(12\)/);
assert.doesNotMatch(track.innerHTML, /product=9/);
assert.deepEqual(events, ['loop', 'translate']);
context.SFReviews.loadRatings = () => Promise.reject(new Error('Ratings unavailable'));
await context.loadSimilar(8, 9);
assert.ok(track.innerHTML.includes(I18N.moneyRange('23', '32')));
assert.match(track.innerHTML, /similar-rating-empty/);
assert.match(track.innerHTML, /similar-verified/);
console.log('PASS similar product supplier, price range, empty stars, expandable tiers, carousel controls, current-product exclusion, and failure fallback');
