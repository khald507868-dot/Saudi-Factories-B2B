import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const page = read('web-product.html');
function functionSource(name) {
  const start = page.indexOf('      function ' + name + '(');
  assert(start >= 0, name);
  const end = page.indexOf('\n      }', start);
  return page.slice(start, end + '\n      }'.length);
}
const functions = ['descCardHTML', 'specsCardHTML', 'global_SFTranslate', 'applyLiveProduct'].map(functionSource).join('\n');
const flush = () => new Promise(resolve => setImmediate(resolve));

for (const language of ['en', 'fr', 'ar', 'unsupported']) {
  const cards = [];
  function element(text = '', attributes = {}) {
    return {
      textContent: text, attributes, classList: { remove() {} },
      getAttribute(key) { return Object.hasOwn(this.attributes, key) ? this.attributes[key] : null; },
      setAttribute(key, value) { this.attributes[key] = value; },
      removeAttribute(key) { delete this.attributes[key]; }
    };
  }
  const title = element();
  const info = {
    querySelector() { return null; },
    appendChild(card) {
      card.holder.children.shift();
      card.parentNode = this;
      cards.push(card);
    },
    removeChild(card) { cards.splice(cards.indexOf(card), 1); }
  };
  const wrap = {
    querySelector(selector) {
      if (selector === '.prod-name') return title;
      if (selector === '.pd-info') return info;
      if (selector === '.add-cart-btn') return {}; // existing purchase controls
      return cards.find(card => '#' + card.id === selector) || null;
    },
    querySelectorAll(selector) {
      assert.equal(selector, '[data-sf-translate]');
      return [title, ...cards.flatMap(card => card.nodes)].filter(el => el.getAttribute('data-sf-translate') !== null);
    }
  };
  const requests = [];
  const context = vm.createContext({
    console, Promise, wrap, product: {}, factory: {}, factoryName: 'Factory',
    basePriceText: '', imageIcon: '',
    I18N: { getLang: () => language, t: key => key },
    escapeHTML: value => String(value), // test fixtures contain no HTML
    syncVerified() {}, loadReviewsBlock() {}, paintThumbs() {}, renderTiers() {},
    document: {
      createElement(tag) {
        assert.equal(tag, 'div');
        return {
          children: [], get firstChild() { return this.children[0]; },
          set innerHTML(html) {
            for (const match of html.matchAll(/<div class="card" id="([^"]+)">([\s\S]*?)(?=<div class="card"|$)/g)) {
              const nodes = Array.from(match[2].matchAll(/<(?:div|td)[^>]* data-sf-translate>([^<]*)<\//g), m => element(m[1], { 'data-sf-translate': '' }));
              this.children.push({ id: match[1], nodes, holder: this });
            }
          }
        };
      }
    },
    Translator: language === 'unsupported' ? undefined : {
      availability: async () => 'available',
      create: async ({ targetLanguage }) => ({ translate: async text => {
        requests.push(text);
        return targetLanguage + ':' + text;
      } })
    }
  });
  context.window = context;
  vm.runInContext(read('translate.js'), context);
  vm.runInContext(functions, context);
  const row = { name: 'تانكي', description: 'وصف المنتج', material: 'حديد', colors: 'أبيض', sizes: 'كبير', moq: 5 };
  const cardName = await context.SFTranslate.translate(row.name, language);
  context.applyLiveProduct(row);
  await flush();
  const expected = text => language === 'ar' || language === 'unsupported' ? text : language + ':' + text;
  assert.equal(title.textContent, cardName, language + ': same name as homepage card');
  assert.equal(title.getAttribute('data-sf-translate'), '');
  assert.equal(title.getAttribute('data-sf-src'), row.name);
  assert.equal(cards.find(card => card.id === 'card-desc').nodes[0].textContent, expected(row.description));
  assert.deepEqual(cards.find(card => card.id === 'card-specs').nodes.map(node => node.textContent), [row.material, row.sizes, row.colors].map(expected));
  if (language === 'en' || language === 'fr') {
    assert.equal(requests.filter(text => text === row.name).length, 1, 'Reuse homepage translation cache');
    assert.equal(requests.some(text => text.includes('product_unit')), false, 'Quantity and UI unit are not machine translated');
  }
  context.applyLiveProduct({ ...row, name: 'الاسم الجديد', description: 'الوصف الجديد' });
  await flush();
  assert.equal(title.textContent, expected('الاسم الجديد'), 'Live product replaces previous translation source');
  assert.equal(cards.find(card => card.id === 'card-desc').nodes[0].textContent, expected('الوصف الجديد'));
  context.applyLiveProduct({ name: 'الاسم الجديد', description: '' });
  await flush();
  assert.equal(cards.length, 0, 'Empty details do not retain stale translated content');
}
console.log('PASS product translation: live title, final description/specs, homepage cache consistency, updated content, Arabic and unavailable translator fallback');
