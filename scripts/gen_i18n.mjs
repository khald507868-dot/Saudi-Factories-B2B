// توليد ترجمات Flutter من المصدر نفسه عند عدم توفر Python.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const root = new URL('../', import.meta.url);
const source = fs.readFileSync(new URL('i18n.js', root), 'utf8');

function literal(name, opening, closing) {
  const marker = `var ${name} = ${opening}`;
  const start = source.indexOf(marker);
  assert(start >= 0, `Missing ${name}`);
  const begin = start + marker.length - 1;
  let depth = 0;
  let quote = '';
  for (let index = begin; index < source.length; index++) {
    const char = source[index];
    if (quote) {
      if (char === '\\') index++;
      else if (char === quote) quote = '';
      continue;
    }
    if (char === '"' || char === "'") { quote = char; continue; }
    if (char === opening) depth++;
    if (char === closing && --depth === 0) {
      return vm.runInNewContext(`(${source.slice(begin, index + 1)})`, Object.create(null), {timeout: 1000});
    }
  }
  throw new Error(`Unclosed ${name}`);
}

const dict = literal('dict', '{', '}');
const regions = literal('regionNames', '{', '}');
const categories = literal('categories', '[', ']');
assert.equal(Object.keys(dict).length, 30);
assert.equal(Object.keys(regions).length, 13);
assert.equal(categories.length, 20);
const keys = Object.keys(dict.ar).sort();
for (const [code, values] of Object.entries(dict)) {
  assert.deepEqual(Object.keys(values).sort(), keys, `Translation keys differ: ${code}`);
  assert(Object.values(values).every(value => typeof value === 'string'));
}
const quote = value => JSON.stringify(value).replaceAll('$', '\\$');
const lines = [
  '// ============================================================',
  '//  ملف مُولَّد آلياً من i18n.js — لا تعدّله يدوياً.',
  '//  أعد توليده بـ: node scripts/gen_i18n.mjs أو python scripts/gen_i18n.py',
  '// ============================================================',
  '',
  'const List<String> kRtlLangs = ["ar", "fa", "ur", "he"];',
  '',
  'const Map<String, Map<String, String>> kRegionNames = {',
  ...Object.entries(regions).map(([key, value]) => `  ${quote(key)}: {"ar": ${quote(value.ar)}, "en": ${quote(value.en)}},`),
  '};', '',
  'const List<Map<String, String>> kCategories = [',
  ...categories.map(value => `  {"ar": ${quote(value.ar)}, "en": ${quote(value.en)}},`),
  '];', '',
  'const Map<String, Map<String, String>> kDict = {',
];
for (const code of ['ar', 'en', ...Object.keys(dict).filter(code => code !== 'ar' && code !== 'en').sort()]) {
  lines.push(`  ${quote(code)}: {`);
  for (const [key, value] of Object.entries(dict[code])) lines.push(`    ${quote(key)}: ${quote(value)},`);
  lines.push('  },');
}
lines.push('};', '');
fs.writeFileSync(new URL('app_flutter/lib/core/i18n_data.dart', root), lines.join('\n'));
console.log(`Generated 30 languages, ${keys.length} keys each, 13 regions, 20 categories.`);
