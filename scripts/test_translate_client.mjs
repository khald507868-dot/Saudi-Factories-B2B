import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../translate.js', import.meta.url), 'utf8');
const input = 'نبذة عن المصنع';
let cache = '{}';
function setup(Translator) {
  const context = vm.createContext({
    Promise, Translator,
    navigator: { userActivation: { isActive: false } },
    sessionStorage: { getItem: () => cache, setItem(key, value) { cache = value; } }
  });
  context.window = context;
  vm.runInContext(source, context);
  return context.SFTranslate;
}
let attempts = 0;
const api = setup({
  availability: async () => 'available',
  create() {
    attempts++;
    if (attempts === 1) throw Object.assign(new Error('Requires gesture'), { name: 'NotAllowedError' });
    return Promise.resolve({ translate: async () => 'Présentation de l’usine' });
  }
});
const states = [];
const options = { onStatus: state => states.push(state) };
assert.equal(await api.translate(input, 'fr', options), input);
assert.equal(states.at(-1), 'activation-required');
assert.equal(await api.translate(input, 'fr', { ...options, userInitiated: true }), 'Présentation de l’usine');
assert.equal(attempts, 2);
assert.equal(states.at(-1), 'translated');
// A new page can reuse the successful result without another activation/download.
assert.equal(await setup(undefined).translate(input, 'fr', options), 'Présentation de l’usine');
assert.equal(states.at(-1), 'translated');

cache = JSON.stringify({ ['ar>fr:' + input]: input });
let calls = 0;
const unchanged = setup({
  availability: async () => 'available',
  create: async () => ({ translate: async () => ++calls === 1 ? input : 'Nouveau texte' })
});
assert.equal(await unchanged.translate(input, 'fr', options), input);
assert.equal(states.at(-1), 'failed', 'Unchanged source is not reported as a successful translation');
assert.equal(await unchanged.translate(input, 'fr', options), 'Nouveau texte', 'Unchanged legacy cache does not block a retry');
assert.equal(calls, 2);

cache = '{}';
const missing = setup(undefined);
assert.equal(await missing.translate(input, 'fr', options), input);
assert.equal(states.at(-1), 'unsupported');
assert.equal(await missing.translate(input, 'ar', options), input);
assert.equal(states.at(-1), 'original');
assert.equal(await missing.translate('', 'fr', options), '');
assert.equal(states.at(-1), 'original');
let translates = 0;
const network = setup({
  availability: async () => 'available',
  create: async () => ({ translate: async () => {
    if (++translates === 1) throw Error('Translation failed');
    return 'Texte traduit';
  } })
});
await network.translate(input, 'fr', options);
assert.equal(states.at(-1), 'failed');
assert.equal(await network.translate(input, 'fr', options), 'Texte traduit');
console.log('PASS translator: sync activation rejection, click retry, navigation cache, unchanged-output retry, unsupported browser and transient translation failure');
