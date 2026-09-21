/* العناوين من حساب المستخدم؛ كل الكتابات تمر بدوال الخادم المحمية. */
(function (root) {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var t = function (key) { return root.I18N.t(key); };
  var fields = ['country', 'city', 'district', 'street', 'building', 'short_address', 'postal_code', 'additional_number', 'latitude', 'longitude'];
  var nationalFields = ['street', 'building', 'short_address', 'postal_code', 'additional_number'];
  var geoFields = ['country', 'city', 'district', 'street', 'building', 'postal_code'];
  function isSaudi(value) { return ['sa','sau','ksa','saudi arabia','kingdom of saudi arabia','السعودية','السعوديه','المملكة العربية السعودية','المملكه العربيه السعوديه'].includes(String(value || '').trim().toLowerCase().replace(/\s+/g, ' ')); }
  function domestic() { return form.elements.address_scope.value === 'domestic'; }
  function syncScope() {
    $('address-saudi-fields').hidden = !domestic();
    $('address-saudi-fields').disabled = !domestic();
    form.elements.country.readOnly = domestic();
    if (domestic()) form.elements.country.value = t('delivery_saudi_country');
  }
  function digits(value) { return value.replace(/[٠-٩]/g, function (c) { return String(c.charCodeAt(0) - 1632); }).replace(/[۰-۹]/g, function (c) { return String(c.charCodeAt(0) - 1776); }); }
  var rows = [], userId, editingId, busy = false, savedView = false, loaded = false, map, marker, mapFailed = false, locationVersion = 0, sessionVersion = 0, detailsVersion = 0;
  var form = $('address-form');
  function status(key, error) {
    $('address-status').textContent = key ? t(key) : '';
    $('address-status').dataset.error = String(!!error);
    $('address-save-status').textContent = key ? t(key) : '';
    $('address-save-status').dataset.error = String(!!error);
  }
  function lock(value) {
    busy = value;
    $('address-fields').disabled = value || savedView;
    $('address-editor').dataset.saved = String(savedView);
    $('address-save').disabled = value || savedView || !loaded;
    $('address-save').textContent = t(savedView ? 'delivery_saved' : 'delivery_save');
    $('address-update').hidden = !savedView;
    $('address-update').disabled = value;
    $('address-cancel').hidden = savedView;
    $('address-cancel').disabled = value;
    $('address-save-hint').hidden = savedView;
    document.querySelectorAll('[data-address-action]').forEach(function (button) { button.disabled = value; });
    $('address-add').disabled = value || !loaded;
    $('address-retry').disabled = value;
    if (marker && marker.dragging) marker.dragging[value || savedView ? 'disable' : 'enable']();
    syncScope();
  }
  function failure(error, fallback) {
    var message = String(error && error.message || '');
    if (/delivery_address_limit/.test(message)) return 'delivery_limit';
    if (/delivery_invalid_national_address/.test(message)) return 'delivery_national_format';
    if (/delivery_invalid/.test(message)) return 'delivery_invalid';
    if (/delivery_country_scope_mismatch/.test(message)) return 'delivery_scope_mismatch';
    if (/delivery_session_changed/.test(message)) return 'delivery_sign_in';
    if (error && ['42P01', '42883', 'PGRST202', 'PGRST205'].includes(error.code)) return 'delivery_setup_required';
    return fallback;
  }
  function node(tag, text, className) {
    var el = document.createElement(tag);
    if (text) el.textContent = text;
    if (className) el.className = className;
    return el;
  }
  function button(key, action) {
    var el = node('button', t(key));
    el.type = 'button';
    el.dataset.addressAction = '';
    el.addEventListener('click', action);
    return el;
  }
  function render() {
    var list = $('address-list');
    list.replaceChildren();
    if (!rows.length) list.append(node('p', t('delivery_empty')));
    rows.forEach(function (row) {
      var card = node('article', '', 'address-card');
      card.dataset.default = String(row.is_default);
      card.append(node('h2', row.label));
      if (row.is_default) card.append(node('span', t('delivery_selected'), 'address-default'));
      card.append(node('p', [row.address_line, row.building, row.floor, row.apartment].filter(Boolean).join(' · ')));
      if (row.notes) card.append(node('p', row.notes, 'address-hint'));
      var actions = node('div', '', 'address-actions');
      actions.append(button('delivery_edit', function () { edit(row); }));
      if (!row.is_default) actions.append(button('delivery_use_default', function () { mutate('select_delivery_address', { p_id: row.id }, 'delivery_default_updated'); }));
      actions.append(button('delivery_delete', function () {
        if (root.confirm(t('delivery_delete_confirm'))) mutate('delete_delivery_address', { p_id: row.id }, 'delivery_deleted');
      }));
      card.append(actions);
      list.append(card);
    });
  }
  async function load() {
    if (busy) return;
    var version = sessionVersion;
    lock(true); status('fx_loading');
    try {
      var result = await root.sb.from('delivery_addresses').select('*').eq('user_id', userId).order('created_at').order('id');
      if (version !== sessionVersion) return;
      if (result.error) throw result.error;
      rows = result.data || []; loaded = true; render(); status('');
      $('address-retry').hidden = true;
      var selected = rows.find(function (row) { return row.is_default; }) || rows[0];
      if (selected) { lock(false); edit(selected, true); }
    } catch (error) {
      status(failure(error, 'delivery_load_failed'), true);
      $('address-retry').hidden = false;
    } finally { lock(false); }
  }
  async function mutate(name, payload, success) {
    if (busy || !loaded) return;
    var version = sessionVersion;
    lock(true); status('fx_loading'); locationVersion++; detailsVersion++;
    $('address-geocode-status').textContent = '';
    try {
      var result = await root.sb.rpc(name, Object.assign({ p_expected_user_id: userId }, payload));
      if (version !== sessionVersion) return;
      if (result.error) throw result.error;
      rows = result.data || [];
      render();
      var saved = name === 'save_structured_delivery_address' && rows.find(function (row) { return row.id === payload.p_address.id; });
      if (saved) {
        lock(false); edit(saved, true); $('address-update').focus({ preventScroll: true });
      } else closeEditor();
      status(success);
    } catch (error) { status(failure(error, 'delivery_sync_failed'), true); }
    finally { lock(false); }
  }
  function validCoordinates(lat, lon) {
    return Number.isFinite(lat) && Number.isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }
  function resetDetails() {
    detailsVersion++;
    $('address-map-details').hidden = true;
  }
  async function lookupDetails(fill) {
    if (savedView || !root.SFDeliveryGeocoding) return;
    var version = ++detailsVersion, location = locationVersion;
    var before = {};
    geoFields.forEach(function (key) { before[key] = form.elements[key].value; });
    var lat = Number(form.elements.latitude.value), lon = Number(form.elements.longitude.value);
    function current() { return version === detailsVersion && location === locationVersion && !busy && !savedView && !$('address-editor').hidden; }
    $('address-map-details').hidden = false;
    $('address-geocode-status').textContent = t('delivery_reading_address');
    try {
      var details = await root.SFDeliveryGeocoding.reverse(lat, lon, current);
      if (!current()) return;
      $('address-geocode-status').textContent = t(details ? 'delivery_details_ready' : 'delivery_address_unavailable');
      if (fill && details) {
        if (details.country && form.elements.country.value === before.country) {
          form.elements.address_scope.value = isSaudi(details.country_code || details.country) ? 'domestic' : 'international';
          if (!domestic()) nationalFields.forEach(function (key) { form.elements[key].value = ''; });
          syncScope();
        }
        geoFields.forEach(function (key) {
          var value = key === 'postal_code' ? details.postcode : details[key];
          if (nationalFields.includes(key) && !domestic()) return;
          if (key === 'country' && domestic()) return;
          if (key === 'building' && !/^[0-9]{4}$/.test(digits(String(value || '')))) return;
          if (key === 'postal_code' && !/^[0-9]{5}$/.test(digits(String(value || '')))) return;
          if (value && form.elements[key].value === before[key]) form.elements[key].value = value;
        });
      }
    } catch (_) {
      if (current()) $('address-geocode-status').textContent = t('delivery_address_unavailable');
    }
  }
  function setLocation(lat, lon, pan, preserveAddress) {
    if (busy || (savedView && !preserveAddress) || !validCoordinates(lat, lon)) return;
    var changed = form.elements.latitude.value && (Number(form.elements.latitude.value) !== lat || Number(form.elements.longitude.value) !== lon);
    locationVersion++;
    form.elements.latitude.value = String(lat);
    form.elements.longitude.value = String(lon);
    $('address-location-status').textContent = t('delivery_pin_selected');
    if (map) {
      if (!marker) marker = root.L.marker([lat, lon], { draggable: true, title: t('delivery_selected_location') }).addTo(map).on('dragend', function () {
        var point = marker.getLatLng().wrap();
        setLocation(point.lat, point.lng, false);
      });
      else marker.setLatLng([lat, lon]);
      if (pan) map.setView([lat, lon], 16);
      if (savedView && marker.dragging) marker.dragging.disable();
    }
    resetDetails();
    if (changed && !preserveAddress) fields.filter(function (key) { return !['latitude','longitude'].includes(key); }).forEach(function (key) { form.elements[key].value = ''; });
    syncScope();
    lookupDetails(!preserveAddress);
  }
  function initMap() {
    // صفحات file:// لا ترسل عنوان موقع صالحاً لخادم الخرائط.
    if (root.location.protocol === 'file:') {
      $('address-map').hidden = true;
      $('address-local-map').hidden = false;
      $('address-location-status').textContent = '';
      return;
    }
    if (map) { map.invalidateSize(); return; }
    $('address-map-retry').hidden = true;
    if (!root.L) {
      $('address-location-status').textContent = t('delivery_map_unavailable');
      $('address-map-retry').hidden = false;
      return;
    }
    mapFailed = false;
    $('address-map').hidden = false;
    map = root.L.map('address-map').setView([24.7136, 46.6753], 6);
    root.L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).on('tileerror', function () {
      mapFailed = true;
      $('address-map').hidden = true;
      $('address-location-status').textContent = t('delivery_map_unavailable');
      $('address-map-retry').hidden = false;
    }).addTo(map);
    map.on('click', function (event) { setLocation(event.latlng.lat, event.latlng.wrap().lng, false); });
  }
  function retryMap() {
    if (busy || savedView) return;
    if (map && mapFailed) { map.remove(); map = null; marker = null; }
    initMap();
    var lat = form.elements.latitude.value, lon = form.elements.longitude.value;
    if (lat && lon) setLocation(Number(lat), Number(lon), true, true);
  }
  function closeEditor() {
    locationVersion++;
    resetDetails();
    $('address-editor').hidden = true;
  }
  function edit(row, readOnly) {
    if (busy || !loaded) return;
    savedView = !!readOnly;
    locationVersion++;
    resetDetails();
    editingId = row ? row.id : root.crypto.randomUUID();
    fields.forEach(function (key) { form.elements[key].value = row && row[key] != null ? String(row[key]) : ''; });
    form.elements.address_scope.value = row && row.address_scope === 'international' ? 'international' : 'domestic';
    $('address-legacy').hidden = !row || ['domestic','international'].includes(row.address_scope);
    $('address-legacy-value').textContent = row && row.address_line || '';
    syncScope();
    $('address-editor').hidden = false;
    $('address-location-status').textContent = t('delivery_map_click_hint');
    status(''); initMap();
    if (marker) { marker.remove(); marker = null; }
    if (row) {
      setLocation(row.latitude, row.longitude, true, true);
      if (!row.country || !row.city) lookupDetails(true);
    }
    lock(false);
    if (!savedView) {
      $('address-editor').scrollIntoView({ block: 'start', behavior: 'smooth' });
      form.elements.city.focus({ preventScroll: true });
    }
  }
  function locate() {
    if (busy || savedView) return;
    if (!root.navigator.geolocation) { $('address-location-status').textContent = t('delivery_location_unavailable'); return; }
    var version = ++locationVersion;
    $('address-location-status').textContent = t('delivery_locating');
    root.navigator.geolocation.getCurrentPosition(function (position) {
      if (version !== locationVersion || busy || savedView || $('address-editor').hidden) return;
      setLocation(position.coords.latitude, position.coords.longitude, true);
    }, function (error) {
      if (version !== locationVersion) return;
      $('address-location-status').textContent = t(error.code === 1 ? 'delivery_location_denied' : 'delivery_location_unavailable');
    }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
  }
  function saveAddress() {
    if (busy || savedView || $('address-editor').hidden) return;
    var address = { id: editingId, address_scope: form.elements.address_scope.value };
    fields.forEach(function (key) { address[key] = form.elements[key].value.trim(); });
    if (!address.latitude || !address.longitude || !validCoordinates(Number(address.latitude), Number(address.longitude))) {
      status('delivery_choose_location', true); $('address-locate').focus(); return;
    }
    if (!address.country || !address.city) { status('delivery_required', true); return; }
    if (domestic() !== isSaudi(address.country)) { status('delivery_scope_mismatch', true); return; }
    nationalFields.forEach(function (key) { address[key] = domestic() ? digits(address[key]) : ''; });
    address.short_address = address.short_address.toUpperCase();
    form.elements.short_address.value = address.short_address;
    ['building','postal_code','additional_number'].forEach(function (key) { form.elements[key].value = address[key]; });
    if (domestic() && ((address.short_address && !/^[A-Z]{4}[0-9]{4}$/.test(address.short_address)) ||
      (address.postal_code && !/^[0-9]{5}$/.test(address.postal_code)) || (address.additional_number && !/^[0-9]{4}$/.test(address.additional_number)) ||
      (address.building && !/^[0-9]{4}$/.test(address.building)))) { status('delivery_national_format', true); return; }
    if (!form.reportValidity()) return;
    address.latitude = Number(address.latitude); address.longitude = Number(address.longitude);
    mutate('save_structured_delivery_address', { p_address: address }, 'delivery_saved');
  }
  form.addEventListener('submit', function (event) { event.preventDefault(); saveAddress(); });
  $('address-save').addEventListener('click', saveAddress);
  $('address-add').addEventListener('click', function () { edit(null); });
  $('address-update').addEventListener('click', function () {
    if (busy || !savedView) return;
    var row = rows.find(function (item) { return item.id === editingId; });
    if (row) edit(row);
  });
  $('address-cancel').addEventListener('click', function () {
    if (busy) return;
    var row = rows.find(function (item) { return item.id === editingId; });
    if (row) edit(row, true); else closeEditor();
  });
  $('address-locate').addEventListener('click', locate);
  $('address-retry').addEventListener('click', load);
  $('address-map-retry').addEventListener('click', retryMap);
  $('address-details-retry').addEventListener('click', function () { if (!busy && !savedView) { resetDetails(); lookupDetails(true); } });
  form.elements.address_scope.addEventListener('change', function () {
    if (busy || savedView) return;
    locationVersion++; resetDetails();
    fields.forEach(function (key) { form.elements[key].value = ''; });
    if (marker) { marker.remove(); marker = null; }
    $('address-location-status').textContent = t('delivery_choose_location');
    syncScope();
  });
  root.SF_AUTH_READY.then(function (user) {
    if (!user) return;
    userId = user.id;
    root.sb.auth.onAuthStateChange(function (event, session) {
      if (event === 'INITIAL_SESSION') return;
      if (!session || session.user.id !== userId) {
        sessionVersion++; locationVersion++; loaded = false; rows = [];
        $('address-list').replaceChildren(); closeEditor(); lock(true);
        root.location.replace('web-login.html?next=web-addresses.html');
      }
    });
    var profile = root.SF_PROFILE || {};
    $('dash-name').textContent = profile.full_name || t('nav_account');
    $('dash-type').textContent = t(profile.account_type === 'factory' ? 'dash_account_factory' : 'dash_account_individual');
    $('address-list').setAttribute('aria-label', t('delivery_choose'));
    $('address-map').setAttribute('aria-label', t('delivery_location'));
    if (profile.company_image && root.sfSafeHttpUrl) {
      var imageUrl = root.sfSafeHttpUrl(profile.company_image);
      if (imageUrl) {
        var avatar = document.createElement('img'); avatar.src = imageUrl; avatar.alt = '';
        $('dash-avatar').replaceChildren(avatar);
      }
    }
    if (profile.is_admin) $('dash-admin').style.display = '';
    if (profile.account_type === 'factory') {
      root.sb.from('factories').select('id').eq('owner_id', userId).maybeSingle().then(function (result) {
        if (!result.error && result.data) {
          $('dash-myfactory').href = 'web-factory.html?id=' + encodeURIComponent(result.data.id);
          $('dash-myfactory').style.display = '';
        }
      });
    }
    load();
  }).catch(function () { status('delivery_load_failed', true); });
})(window);
