import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
const page = read('web-factory.html');
const extract = name => {
  const start = page.indexOf('      function ' + name + '(');
  assert(start >= 0);
  return page.slice(start, page.indexOf('\n      }', start) + '\n      }'.length);
};
const flush = () => new Promise(resolve => setImmediate(resolve));
function setup({ owner = false, supported = true, lang = 'en', deferred = false, availability = 'available', downloadFailure = false } = {}) {
  const nodes = new Map();
  function element(id = '') {
    const classes = new Set();
    return {
      id, textContent: '', value: '', attrs: {}, style: {}, listeners: {},
      addEventListener(type, callback) { this.listeners[type] = callback; },
      focus() {},
      classList: { add: x => classes.add(x), contains: x => classes.has(x), toggle(x, enabled) { if (enabled) classes.add(x); else classes.delete(x); } },
      setAttribute(key, value) { this.attrs[key] = value; },
      getAttribute(key) { return this.attrs[key] ?? null; }
    };
  }
  const node = id => { if (!nodes.has(id)) nodes.set(id, element(id)); return nodes.get(id); };
  const input = node('factory-about');
  input.value = 'نبذة أصلية';
  input.parentNode = {
    replaceChild(el, old) { assert.equal(old, input); nodes.set(el.id, el); },
    insertBefore(el) { nodes.set(el.id, el); }
  };
  const saved = [];
  const pending = [];
  let createCount = 0;
  const context = vm.createContext({
    Promise, canEdit: owner, aboutEditing: false, aboutInput: input, data: { about: input.value },
    save() { saved.push(context.data.about); },
    navigator: { userActivation: { isActive: false } },
    I18N: { getLang: () => lang, t: key => key },
    safeExternalUrl: x => x, industryLabel: () => '', hqText: () => '',
    document: { getElementById: node, createElement: () => element() },
    Translator: supported ? {
      availability: async () => availability,
      create: async ({ targetLanguage, monitor }) => {
        createCount++;
        if (availability === 'downloadable' && !context.navigator.userActivation.isActive) {
          throw Object.assign(new Error('User activation required'), { name: 'NotAllowedError' });
        }
        if (monitor) monitor({ addEventListener(type, callback) { callback({ loaded: .5 }); } });
        if (downloadFailure) { downloadFailure = false; throw Error('Download interrupted'); }
        return { translate: text => {
        if (deferred) return new Promise(resolve => pending.push({ text, resolve }));
        return Promise.resolve(targetLanguage + ':' + text);
      } }; }
    } : undefined
  });
  context.window = context;
  vm.runInContext(read('translate.js'), context);
  vm.runInContext(['showAsText', 'initAboutEditor', 'translateOverview', 'renderAbout'].map(extract).join('\n'), context);
  if (!owner) context.showAsText(input, context.data.about, 'empty', '');
  else context.initAboutEditor();
  return { context, node, input, pending, saved, createCount: () => createCount };
}

for (const lang of ['en', 'fr', 'ar']) {
  const { context, node } = setup({ lang });
  context.renderAbout(); await flush();
  assert.equal(node('factory-about-read').textContent, lang === 'ar' ? 'نبذة أصلية' : lang + ':نبذة أصلية');
  context.data.about = 'نبذة محدثة من الخادم';
  context.renderAbout(); await flush();
  assert.equal(node('factory-about-read').textContent, lang === 'ar' ? context.data.about : lang + ':' + context.data.about);
  assert.equal(context.data.about, 'نبذة محدثة من الخادم', 'Translation must not change the saved source');
  context.data.about = '';
  context.renderAbout(); await flush();
  assert.equal(node('factory-about-read').textContent, '');
  assert.equal(node('card-about').classList.contains('is-empty'), true);
  context.data.about = 'نبذة جديدة';
  context.renderAbout(); await flush();
  assert.equal(node('card-about').classList.contains('is-empty'), false);
}
const owner = setup({ owner: true });
owner.context.renderAbout(); await flush();
assert.equal(owner.input.value, 'نبذة أصلية', 'Keep owner editing the original source');
assert.equal(owner.input.style.display, 'none', 'Owner starts in translated preview');
assert.equal(owner.node('factory-about-read').textContent, 'en:نبذة أصلية');
owner.node('factory-about-edit').listeners.click();
assert.equal(owner.input.style.display, '');
assert.equal(owner.input.value, 'نبذة أصلية', 'Edit source rather than translated preview');
owner.input.value = 'تعديل عربي جديد';
owner.input.listeners.input();
assert.deepEqual(owner.saved, ['تعديل عربي جديد'], 'Only original text is saved');
owner.context.renderAbout(); await flush();
assert.equal(owner.input.value, 'تعديل عربي جديد', 'Rerenders preserve ongoing edits');
owner.node('factory-about-edit').listeners.click(); await flush();
assert.equal(owner.input.style.display, 'none');
assert.equal(owner.node('factory-about-read').textContent, 'en:تعديل عربي جديد');
assert.equal(owner.context.data.about, 'تعديل عربي جديد');
owner.context.data.about = 'نبذة الخادم';
owner.context.renderAbout(); await flush();
assert.equal(owner.node('factory-about-read').textContent, 'en:نبذة الخادم');
owner.context.data.about = '';
owner.context.renderAbout(); await flush();
assert.equal(owner.node('card-about').classList.contains('is-empty'), false, 'Owner can edit an empty overview');
const unavailable = setup({ supported: false });
unavailable.context.renderAbout(); await flush();
assert.equal(unavailable.node('factory-about-read').textContent, 'نبذة أصلية');
assert.equal(unavailable.node('about-translation-status').textContent, 'translation_unavailable');
assert.equal(unavailable.node('about-translation-retry').hidden, true);

const french = setup({ lang: 'fr', availability: 'downloadable' });
french.context.renderAbout(); await flush();
assert.equal(french.node('about-translation-status').textContent, 'translation_activation');
assert.equal(french.node('about-translation-retry').hidden, false);
assert.equal(french.createCount(), 0, 'Do not attempt model download without activation');
french.context.navigator.userActivation.isActive = true;
french.node('about-translation-retry').onclick();
assert.equal(french.createCount(), 1, 'Start download synchronously during user click');
assert.match(french.node('about-translation-status').textContent, /50%/);
await flush();
assert.equal(french.node('factory-about-read').textContent, 'fr:نبذة أصلية');
assert.equal(french.node('about-translation').hidden, true);

const failure = setup({ lang: 'fr', availability: 'downloadable', downloadFailure: true });
failure.context.renderAbout(); await flush();
failure.context.navigator.userActivation.isActive = true;
failure.node('about-translation-retry').onclick(); await flush();
assert.equal(failure.node('about-translation-status').textContent, 'translation_failed');
assert.equal(failure.node('about-translation-retry').hidden, false);
failure.node('about-translation-retry').onclick(); await flush();
assert.equal(failure.createCount(), 2, 'Failed creation must not poison future retries');
assert.equal(failure.node('factory-about-read').textContent, 'fr:نبذة أصلية');

const noPair = setup({ availability: 'unavailable', lang: 'fr' });
noPair.context.renderAbout(); await flush();
assert.equal(noPair.node('about-translation-status').textContent, 'translation_unavailable');
assert.equal(noPair.createCount(), 0);

const race = setup({ deferred: true });
race.context.renderAbout(); await flush();
race.context.data.about = 'نبذة جديدة';
race.context.renderAbout(); await flush();
assert.equal(race.pending.length, 2);
race.pending[1].resolve('New overview'); await flush();
race.pending[0].resolve('Old overview'); await flush();
assert.equal(race.node('factory-about-read').textContent, 'New overview', 'Slow draft translation cannot replace the live text');
race.context.data.about = 'نبذة مؤقتة';
race.context.renderAbout(); await flush();
race.context.data.about = '';
race.context.renderAbout();
race.pending[2].resolve('Removed overview'); await flush();
assert.equal(race.node('factory-about-read').textContent, '', 'Pending translation cannot restore a deleted overview');
console.log('PASS factory overview: visitor translation, live refresh, source preservation, owner editor, empty content, unsupported browser and stale requests');
