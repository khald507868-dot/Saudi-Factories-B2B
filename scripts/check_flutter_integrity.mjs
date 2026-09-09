// يتحقق من أن المفاتيح التي تستعملها صفحات Flutter موجودة في المصدر المولّد.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
const lib = path.join(root, 'app_flutter/lib');
const dictionary = fs.readFileSync(path.join(lib, 'core/i18n_data.dart'), 'utf8');
assert(!/\?{3,}/.test(dictionary), 'Translation contains corrupted question-mark placeholders');
const keys = new Set([...dictionary.matchAll(/^    "([a-zA-Z0-9_]+)":/gm)].map(match => match[1]));
const missing = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file);
    else if (entry.name.endsWith('.dart') && entry.name !== 'i18n_data.dart') {
      const source = fs.readFileSync(file, 'utf8');
      for (const match of source.matchAll(/\.t\(\s*'([a-zA-Z0-9_]+)'/g)) {
        if (!keys.has(match[1])) missing.push(`${path.relative(root, file)}: ${match[1]}`);
      }
    }
  }
}
walk(lib);
assert.equal(missing.length, 0, missing.join('\n'));
console.log(`Flutter translation references verified (${keys.size} keys).`);
