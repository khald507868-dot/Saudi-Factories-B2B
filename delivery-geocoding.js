/* بيانات وصف الموقع من المصدر المستخدم في تطبيق الجوال؛ لا تُولّد أرقاماً وطنية. */
(function (root) {
  'use strict';
  var cache = new Map(), queue = Promise.resolve(), lastRequest = 0;
  function parse(data) {
    if (!data || !Array.isArray(data.features)) throw new Error('invalid_geocoder_response');
    var feature = data.features[0];
    if (!feature) return null;
    var p = feature.properties;
    if (!p || typeof p !== 'object') throw new Error('invalid_geocoder_response');
    function text(key, max) { return typeof p[key] === 'string' ? p[key].trim().slice(0, max || 150) : ''; }
    var result = {
      street: text('street'), postcode: text('postcode', 40), building: text('housenumber', 80),
      district: text('district', 100), city: text('city', 100), country: text('country', 100), country_code: text('countrycode', 2)
    };
    // رقم المبنى يبقى في خانته المنفصلة، والشارع والرمز البريدي ضمن العنوان المحفوظ.
    result.address = Array.from(new Set([text('name'), result.street, result.district, result.city, text('state'), result.postcode, result.country].filter(Boolean))).join('، ').slice(0, 500);
    return result.address || result.building ? result : null;
  }
  function reverse(lat, lon, isCurrent) {
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) return Promise.reject(new Error('invalid_coordinates'));
    var params = new URLSearchParams({ lat: lat.toFixed(6), lon: lon.toFixed(6), limit: '1', radius: '0.1' });
    if (root.I18N.getLang() !== 'ar') params.set('lang', 'en');
    var url = 'https://photon.komoot.io/reverse?' + params;
    if (cache.has(url)) return Promise.resolve(cache.get(url));
    var request = queue.then(async function () {
      if (!isCurrent()) return null;
      var wait = Math.max(0, 1100 - (Date.now() - lastRequest));
      if (wait) await new Promise(function (resolve) { root.setTimeout(resolve, wait); });
      if (!isCurrent()) return null;
      lastRequest = Date.now();
      var controller = new AbortController();
      var timeout = root.setTimeout(function () { controller.abort(); }, 10000);
      try {
        var response = await root.fetch(url, { signal: controller.signal, credentials: 'omit', headers: { Accept: 'application/json' } });
        if (!response.ok) throw new Error('geocoder_unavailable');
        var result = parse(await response.json());
        if (cache.size >= 40) cache.delete(cache.keys().next().value);
        cache.set(url, result);
        return result;
      } finally { root.clearTimeout(timeout); }
    });
    queue = request.catch(function () {});
    return request;
  }
  root.SFDeliveryGeocoding = { reverse: reverse };
})(window);
