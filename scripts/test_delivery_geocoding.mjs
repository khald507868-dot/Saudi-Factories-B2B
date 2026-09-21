// عقد خدمة العنوان وحدود طلباتها، دون شبكة أو بيانات مستخدمين.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
let now = 2000, response = {}, ok = true;
const calls = [];
const window = {
  I18N: { getLang: () => 'ar' },
  setTimeout(callback, delay) { if (delay < 10000) { now += delay; queueMicrotask(callback); } return 1; },
  clearTimeout() {},
  async fetch(url, options) { calls.push({ url: new URL(url), options, at: now }); return { ok, json: async () => response }; }
};
vm.runInNewContext(fs.readFileSync(new URL('../delivery-geocoding.js', import.meta.url), 'utf8'), { window, URLSearchParams, AbortController, Date: { now: () => now } });
const reverse = (lat = 24.7, lon = 46.7, current = () => true) => window.SFDeliveryGeocoding.reverse(lat, lon, current);
response = { features: [{ properties: { street: 'Street', housenumber: '1234', postcode: '12345', city: 'Riyadh', country: 'Saudi Arabia' } }] };
const details = await reverse();
assert.equal(details.building, '1234'); assert.equal(details.postcode, '12345');
assert(details.address.includes('Street')); assert(details.address.includes('12345'));
assert(!Object.hasOwn(details, 'short_address'));
assert.equal(calls[0].options.credentials, 'omit');
assert.equal(calls[0].url.searchParams.get('lat'), '24.700000');
assert.equal(calls[0].url.searchParams.get('radius'), '0.1');
await reverse(); assert.equal(calls.length, 1);
response = { features: [{ properties: { street: 'Street only' } }] };
const partial = await reverse(24.8);
assert.equal(partial.building, ''); assert.equal(partial.postcode, '');
assert(calls[1].at - calls[0].at >= 1100);
response = { features: [] }; assert.equal(await reverse(24.9), null);
const count = calls.length;
assert.equal(await reverse(25, 47, () => false), null); assert.equal(calls.length, count);
await assert.rejects(() => reverse(91), /invalid_coordinates/);
response = { unexpected: true }; await assert.rejects(() => reverse(25), /invalid_geocoder_response/);
ok = false; await assert.rejects(() => reverse(25.1), /geocoder_unavailable/);
ok = true; response = { features: [] }; assert.equal(await reverse(25.1), null);
console.log('PASS address components, no invented national code, empty results, rate limiting, cache, stale queue and error recovery');
