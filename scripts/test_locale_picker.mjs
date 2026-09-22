import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

class Element {
  constructor(tag) { this.tagName = tag; this.children = []; this.handlers = {}; this.attrs = {}; this.style = {}; this.value = ''; this.offsetHeight = 420; this.hidden = false; }
  appendChild(node) { this.children.push(node); node.parentNode = this; return node; }
  insertBefore(node, next) { const index = this.children.indexOf(next); if (index < 0) return this.appendChild(node); this.children.splice(index, 0, node); node.parentNode = this; return node; }
  setAttribute(key, value) { this.attrs[key] = value; }
  removeAttribute(key) { delete this.attrs[key]; }
  addEventListener(type, handler) { this.handlers[type] = handler; }
  contains(node) { return node === this || this.children.some(child => child.contains(node)); }
  querySelector(selector) { return selector === 'a[href="web-cart.html"]' ? this.children.find(node => node.href === 'web-cart.html') : null; }
  getBoundingClientRect() { return this.rect || { left: 700, right: 740, width:40, top: 20, bottom: 60 }; }
  focus() { this.focused = true; }
}
const head = new Element('head'), body = new Element('body');
const handlers = {};
const flatten = node => [node, ...node.children.flatMap(flatten)];
const document = {
  head, body, readyState:'loading', documentElement:{dir:'rtl'},
  createElement: tag => new Element(tag),
  getElementById: id => [...flatten(head),...flatten(body)].find(node => node.id === id),
  querySelectorAll: () => [],
  addEventListener(type, handler) { (handlers[type] ||= []).push(handler); }
};
const storage = new Map([['sf_lang','ar'],['sf_currency','SAR']]);
const localStorage = { getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value) };
let reloads = 0;
const window = { document, localStorage, innerWidth:1024, innerHeight:800, location:{reload(){reloads++;}}, addEventListener(){} };
const context = vm.createContext({ window, document, localStorage });
for (const path of ['currency.js','i18n.js','currency-ui.js','lang-switch.js']) vm.runInContext(fs.readFileSync(new URL('../'+path,import.meta.url),'utf8'),context,{filename:path});
assert.equal(window.SFCurrencyUI.mount(), false);
const actions = body.appendChild(new Element('div')); actions.id = 'dt-actions';
const cart = actions.appendChild(new Element('a')); cart.href = 'web-cart.html';
window.SFCurrencyUI.mount(); window.SFCurrencyUI.mount();
assert.equal(actions.children.length, 2);
assert.equal(flatten(body).filter(node => node.id === 'sf-locale-btn').length, 1);
assert(!document.getElementById('sf-lang-btn'));
const button = document.getElementById('sf-locale-btn');
const panel = document.getElementById('sf-locale-panel');
const language = document.getElementById('sf-locale-language');
const currency = document.getElementById('sf-locale-currency');
const languageOptions = document.getElementById('sf-locale-language-options');
const currencyOptions = document.getElementById('sf-locale-currency-options');
assert.equal(languageOptions.children.length, 30); assert.equal(currencyOptions.children.length, 30);
assert.equal(flatten(body).filter(node => node.tagName === 'select').length, 0);
assert.equal(button.attrs['aria-haspopup'], 'dialog'); assert.equal(panel.attrs.role, 'dialog');
assert(panel.hidden);
window.SFLang.open();
assert.equal(language.value, 'ar'); assert.equal(currency.value, 'SAR'); assert(!panel.hidden);
language.value = 'en'; currency.value = 'USD';
assert.equal(storage.get('sf_lang'), 'ar'); assert.equal(storage.get('sf_currency'), 'SAR');
handlers.keydown.forEach(fn => fn({key:'Escape',preventDefault(){}}));
assert(panel.hidden); assert.equal(reloads, 0);
window.SFCurrencyUI.open();
assert.equal(language.value, 'ar'); assert.equal(currency.value, 'SAR');
language.value = 'en'; currency.value = 'USD';
let prevented = false; panel.handlers.submit({preventDefault(){prevented=true;}});
assert(prevented); assert.equal(storage.get('sf_lang'), 'en'); assert.equal(storage.get('sf_currency'), 'USD');
assert.equal(window.SFCurrency.getCode(), 'USD'); assert.equal(reloads, 1);
assert(panel.hidden); assert.equal(button.attrs['aria-expanded'], 'false');
window.SFCurrencyUI.open(); panel.handlers.submit({preventDefault(){}});
assert.equal(reloads, 1);
console.log('PASS one combined button, all supported options, draft selection, cancel/reset, saved preferences and one reload');

window.SFCurrencyUI.open();
language.value = 'xx'; currency.value = 'NOT_A_CURRENCY'; panel.handlers.submit({preventDefault(){}});
assert.equal(reloads, 1); assert.equal(storage.get('sf_lang'), 'en');
window.SFCurrencyUI.close();
window.innerWidth = 320; window.innerHeight = 500;
for (const dir of ['rtl','ltr']) {
  document.documentElement.dir = dir; window.SFCurrencyUI.open();
  const left = parseFloat(panel.style.left), top = parseFloat(panel.style.top);
  assert(left >= 12 && left <= 12); assert(top >= 12 && top + panel.offsetHeight <= window.innerHeight - 12);
  handlers.pointerdown.forEach(fn => fn({target:cart})); assert(panel.hidden);
}
assert.equal(storage.get('sf_currency'), 'USD');
assert.equal(storage.get('sf_lang'), 'en');
console.log('PASS invalid-option rejection, outside dismissal, viewport positioning in both directions and unchanged currency conversion');

window.innerWidth = 1024; window.innerHeight = 800; document.documentElement.dir = 'rtl';
window.SFCurrencyUI.open();
language.rect = {left:400,right:716,width:316,top:180,bottom:224};
currency.rect = {left:400,right:716,width:316,top:600,bottom:644};
language.handlers.click();
assert(!languageOptions.hidden); assert(currencyOptions.hidden);
assert.equal(parseFloat(languageOptions.style.top), language.rect.bottom + 6);
assert.equal(parseFloat(languageOptions.style.width), language.rect.width);
assert.equal(parseFloat(languageOptions.style.maxHeight), 280);
assert.equal(language.attrs['aria-expanded'], 'true');
const key = value => ({key:value,preventDefault(){},stopPropagation(){}});
language.handlers.keydown(key('Home'));
language.handlers.keydown(key('Enter'));
assert.equal(language.value, 'ar'); assert(languageOptions.hidden);
assert.equal(storage.get('sf_lang'), 'en');
language.handlers.click(); currency.handlers.click();
assert(languageOptions.hidden); assert(!currencyOptions.hidden);
assert.equal(parseFloat(currencyOptions.style.top), currency.rect.bottom + 6);
assert(parseFloat(currencyOptions.style.maxHeight) <= window.innerHeight - currency.rect.bottom - 18);
currencyOptions.children[0].handlers.click();
assert.equal(currency.value, 'SAR'); assert(currencyOptions.hidden);
assert.equal(storage.get('sf_currency'), 'USD');
currency.handlers.click(); currency.handlers.keydown(key('Escape'));
assert(currencyOptions.hidden); assert(!panel.hidden);
language.handlers.click(); language.handlers.keydown(key('Tab'));
assert(languageOptions.hidden);
panel.handlers.submit({preventDefault(){}});
assert.equal(storage.get('sf_lang'), 'ar'); assert.equal(storage.get('sf_currency'), 'SAR'); assert.equal(reloads, 2);
console.log('PASS custom lists open below their fields, fit available height, allow one list at a time and support keyboard/mouse draft selection');
