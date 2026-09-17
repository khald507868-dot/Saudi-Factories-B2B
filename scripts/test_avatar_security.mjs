// تشغيل مقاطع العرض الفعلية دون متصفح أو اتصال بالشبكة.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const read = f => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
const config = read('supabase-config.js');
let count = 0;
for (const file of ['web-favorites.html','web-invoices.html','web-orders.html']) {
  const page = read(file);
  const start = page.indexOf('    if (avaEl && SF_PROFILE.company_image) {');
  assert(start !== -1);
  const fragment = page.slice(start, page.indexOf('    var adminLink', start));
  for (const value of ['https://example.com/avatar.png', 'https://example.com/x" onerror="alert(1)', 'javascript:alert(1)', 'data:image/svg+xml,<svg onload="alert(1)">', 'file:///private.png']) {
    const avatar = {
      children: [],
      set innerHTML(_) { throw new Error('Untrusted HTML parsing'); },
      replaceChildren(...children) { this.children = children; },
    };
    const context = vm.createContext({URL, URLSearchParams,
      window: {location: {href: 'https://example.com/web-orders.html'}, supabase: {createClient() { return {}; }}},
      document: {createElement(tag) { assert.equal(tag, 'img'); return {style: {}}; }},
      avaEl: avatar, SF_PROFILE: {company_image: value},
    });
    vm.runInContext(config, context);
    vm.runInContext(fragment, context);
    if (value.startsWith('https:')) {
      assert.equal(avatar.children.length, 1);
      assert.equal(avatar.children[0].src, new URL(value).href);
      assert.equal(avatar.children[0].alt, '');
      assert.equal(avatar.children[0].onerror, undefined);
    } else assert.equal(avatar.children.length, 0);
    count++;
  }
}
console.log(`PASS ${count} avatar cases: valid images, quote injection, JavaScript, data and file schemes`);
