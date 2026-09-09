// حدود المناطق من ملف الويب نفسه، مع الاحتفاظ بإسناد OpenStreetMap.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync(new URL('../regions-geo.js', import.meta.url), 'utf8');
const regions = vm.runInNewContext(source + '; SA_REGION_BOUNDS', {}, {timeout: 1000});
assert.equal(Object.keys(regions).length, 13);
const directory = new URL('../app_flutter/assets/', import.meta.url);
fs.mkdirSync(directory, {recursive: true});
fs.writeFileSync(new URL('saudi_regions.json', directory), JSON.stringify(regions));
console.log('Generated 13 Saudi regions from OpenStreetMap source.');
