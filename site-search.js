/* البحث العام في أسماء المصانع والمنتجات المنشورة؛ تبقى الصلاحيات في قاعدة البيانات. */
(function (root) {
  'use strict';
  var PAGE_SIZE = 20;
  var popupCount = 0;
  function normalize(value) {
    return String(value || '').replace(/\*/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 120);
  }
  function pattern(value) { return '%' + normalize(value).replace(/[\\%_]/g, '\\$&') + '%'; }
  function t(key) { return root.I18N.t(key); }
  function fold(value) {
    return normalize(value).toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f\u064b-\u065f\u0670\u0640]/g, '')
      .replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه');
  }
  function distance(a, b) {
    var rows = Array.from({ length: a.length + 1 }, function (_, i) { return [i]; });
    for (var j = 0; j <= b.length; j++) rows[0][j] = j;
    for (var i = 1; i <= a.length; i++) for (j = 1; j <= b.length; j++) {
      rows[i][j] = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) rows[i][j] = Math.min(rows[i][j], rows[i - 2][j - 2] + 1);
    }
    return rows[a.length][b.length];
  }
  function score(name, term) {
    name = fold(name); term = fold(term);
    if (name === term) return 100;
    if (name.includes(term)) return 90 + (name.startsWith(term) ? 5 : 0);
    var words = name.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
    var tokens = term.split(/[^\p{L}\p{N}]+/u).filter(Boolean).slice(0, 6);
    if (!tokens.length) return 0;
    var values = tokens.map(function (token) {
      var best = 0;
      words.forEach(function (word) {
        if (word === token) best = Math.max(best, 85);
        else if (token.length >= 2 && word.includes(token)) best = Math.max(best, 75);
        else if (token.length >= 3 && Math.abs(word.length - token.length) <= 2) {
          var delta = distance(word, token), allowed = token.length >= 6 ? 2 : 1;
          if (delta <= allowed) best = Math.max(best, 65 - delta * 10);
        }
      });
      return best;
    });
    return values.every(function (value) { return value > 0; }) ? values.reduce(function (a, b) { return a + b; }, 0) / values.length : 0;
  }
  function catalogue(client, kind) {
    if (kind === 'products') return client.from('products')
      .select('id,name,price,tiers,image,images,factories!inner(name,status)').eq('factories.status', 'approved');
    if (kind === 'factories') return client.from('factories').select('id,name,logo,cover,status').eq('status', 'approved');
    throw new Error('Invalid search type');
  }
  async function suggestions(client, kind, term) {
    term = normalize(term);
    if (!term) return [];
    var exact = await catalogue(client, kind).ilike('name', pattern(term)).order('name').order('id').range(0, 7);
    if (!exact || exact.error) throw new Error('Search unavailable');
    var candidates = exact.data || [];
    // نبحث عن أجزاء الكلمة في الخادم، ثم نرتب المرشحين حسب قرب الاسم؛ لا نحمل الكتالوج كاملاً.
    var probes = new Set();
    [term, fold(term)].forEach(function (value) {
      value.split(/[^\p{L}\p{N}]+/u).filter(Boolean).slice(0, 6).forEach(function (token) {
        if (token.length < 3) { if (token.length >= 2) probes.add(token); return; }
        var mid = Math.floor(token.length / 2);
        probes.add(token.slice(0, mid)); probes.add(token.slice(-mid));
        if (token.length <= 4) for (var i = 0; i < token.length; i++) probes.add(token.slice(0, i) + token.slice(i + 1));
      });
    });
    var usable = Array.from(probes).filter(function (token) { return token.length >= 2; }).slice(0, 12);
    if (candidates.length < 8 && usable.length) {
      // اقتباس قيمة الفلتر يمنع الفواصل والأقواس من التحول إلى شروط إضافية.
      var filter = usable.map(function (token) { return 'name.ilike.' + JSON.stringify(pattern(token)); }).join(',');
      var nearby = await catalogue(client, kind).or(filter).order('name').order('id').range(0, 119);
      if (!nearby || nearby.error) { if (!candidates.length) throw new Error('Search unavailable'); }
      else candidates = candidates.concat(nearby.data || []);
    }
    var unique = new Map();
    candidates.forEach(function (row) { unique.set(String(row.id), row); });
    return Array.from(unique.values()).map(function (row) { return { row: row, value: score(row.name, term) }; })
      .filter(function (item) { return item.value > 0; })
      .sort(function (a, b) { return b.value - a.value || String(a.row.name).localeCompare(String(b.row.name)); })
      .slice(0, 8).map(function (item) { return item.row; });
  }
  function liveSearch(form, input) {
    var popup = document.createElement('div'); popup.className = 'site-search-suggestions';
    popup.id = 'site-search-suggestions-' + (++popupCount); popup.hidden = true;
    popup.setAttribute('aria-label', t('catalog_search_results')); form.appendChild(popup);
    input.setAttribute('aria-controls', popup.id); input.setAttribute('aria-expanded', 'false'); input.autocomplete = 'off';
    var timer, generation = 0, composing = false;
    function close() { clearTimeout(timer); generation++; popup.hidden = true; input.setAttribute('aria-expanded', 'false'); }
    function open() { popup.hidden = false; input.setAttribute('aria-expanded', 'true'); }
    async function load(term, version) {
      try {
        await (root.SF_AUTH_READY || Promise.resolve());
        if (version !== generation) return;
        var groups = await Promise.allSettled(['products', 'factories'].map(function (kind) { return suggestions(root.sb, kind, term); }));
        if (version !== generation || normalize(input.value) !== term) return;
        popup.replaceChildren();
        var count = 0;
        groups.forEach(function (group, index) {
          var kind = index === 0 ? 'products' : 'factories';
          if (group.status === 'fulfilled' && group.value.length) {
            addText(popup, 'h3', t(index === 0 ? 'factory_products_title' : 'nav_factories'), 'site-search-group');
            group.value.slice(0, index === 0 ? 6 : 3).forEach(function (row) { popup.appendChild(card(row, kind)); count++; });
          } else if (group.status === 'rejected') addText(popup, 'p', t('catalog_search_failed'), 'site-search-message');
        });
        if (!count && groups.every(function (group) { return group.status === 'fulfilled'; })) addText(popup, 'p', t('no_results'), 'site-search-message');
        var all = addText(popup, 'a', t('catalog_search_view_all'), 'site-search-all');
        all.href = 'web-search.html?q=' + encodeURIComponent(term);
        var announcement = addText(popup, 'span', String(count) + ' — ' + t('catalog_search_results'), 'site-search-announcement');
        announcement.setAttribute('role', 'status');
      } catch (_) {
        if (version === generation) { popup.replaceChildren(); addText(popup, 'p', t('catalog_search_failed'), 'site-search-message'); }
      }
    }
    function changed() {
      clearTimeout(timer); var version = ++generation, term = normalize(input.value);
      if (composing || !term) { close(); return; }
      popup.replaceChildren(); addText(popup, 'p', t('fx_loading'), 'site-search-message').setAttribute('role', 'status'); open();
      timer = setTimeout(function () { load(term, version); }, 280);
    }
    input.addEventListener('input', changed);
    input.addEventListener('compositionstart', function () { composing = true; close(); });
    input.addEventListener('compositionend', function () { composing = false; changed(); });
    input.addEventListener('focus', function () { if (normalize(input.value) && popup.hidden) changed(); });
    form.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { event.preventDefault(); input.focus(); close(); return; }
      if (popup.hidden || !['ArrowDown', 'ArrowUp'].includes(event.key)) return;
      var links = Array.from(popup.querySelectorAll('a')); if (!links.length) return;
      event.preventDefault(); var at = links.indexOf(document.activeElement);
      links[(at + (event.key === 'ArrowDown' ? 1 : links.length - 1) + links.length) % links.length].focus();
    });
    document.addEventListener('pointerdown', function (event) { if (!form.contains(event.target)) close(); });
    form.addEventListener('focusout', function (event) { if (!form.contains(event.relatedTarget)) close(); });
  }
  function bind() {
    document.querySelectorAll('.search-box').forEach(function (box) {
      if (box.dataset.searchBound) return;
      var input = box.querySelector('input');
      if (!input) return;
      var form = box;
      if (box.tagName !== 'FORM') {
        form = document.createElement('form');
        form.className = box.className;
        while (box.firstChild) form.appendChild(box.firstChild);
        box.replaceWith(form);
      }
      form.dataset.searchBound = 'true';
      form.setAttribute('role', 'search');
      form.action = 'web-search.html';
      form.method = 'get';
      input.type = 'search'; input.name = 'q'; input.maxLength = 120; input.required = true;
      input.setAttribute('aria-label', t('search_placeholder'));
      var icon = form.querySelector('svg');
      var button = form.querySelector('button[type="submit"]');
      if (!button) {
        button = document.createElement('button'); button.type = 'submit'; button.className = 'site-search-submit';
        if (icon) { icon.setAttribute('aria-hidden', 'true'); button.appendChild(icon); }
        else button.textContent = t('catalog_search_action');
        form.insertBefore(button, input);
      }
      button.setAttribute('aria-label', t('catalog_search_action'));
      button.title = t('catalog_search_action');
      liveSearch(form, input);
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        var term = normalize(input.value);
        if (!term) { input.value = ''; input.focus(); input.reportValidity(); return; }
        root.location.assign('web-search.html?q=' + encodeURIComponent(term));
      });
    });
  }
  async function fetchPage(client, kind, term, offset) {
    term = normalize(term);
    if (!term) return { rows: [], more: false };
    var query = catalogue(client, kind);
    var result = await query.ilike('name', pattern(term)).order('name').order('id').range(offset, offset + PAGE_SIZE);
    if (!result || result.error) throw new Error('Search unavailable');
    var rows = result.data || [];
    if (!rows.length && offset === 0) return { rows: await suggestions(client, kind, term), more: false, similar: true };
    return { rows: rows.slice(0, PAGE_SIZE), more: rows.length > PAGE_SIZE };
  }
  function addText(parent, tag, value, className) {
    var element = document.createElement(tag);
    element.textContent = value || '';
    if (className) element.className = className;
    parent.appendChild(element);
    return element;
  }
  function card(row, kind) {
    var link = document.createElement('a'); link.className = 'catalog-card';
    link.href = (kind === 'products' ? 'web-product.html?id=' : 'web-factory.html?id=') + encodeURIComponent(row.id);
    var visual = document.createElement('div'); visual.className = 'catalog-card-image'; link.appendChild(visual);
    var raw = kind === 'products' ? row.image || (Array.isArray(row.images) && row.images[0]) : row.logo || row.cover;
    var url = root.sfSafeHttpUrl(raw);
    if (url) {
      var img = document.createElement('img'); img.src = url; img.alt = ''; img.loading = 'lazy';
      img.addEventListener('error', function () { img.remove(); }); visual.appendChild(img);
    }
    var content = document.createElement('div'); content.className = 'catalog-card-body'; link.appendChild(content);
    addText(content, 'h3', row.name);
    if (kind === 'products') {
      addText(content, 'p', row.factories && row.factories.name, 'catalog-factory-name');
      var price = addText(content, 'p', '', 'catalog-price');
      if (row.price) price.innerHTML = root.SFProductCard ? root.SFProductCard.priceHTML(row) : root.I18N.money(row.price);
      else price.textContent = t('product_price_on_request');
    }
    return link;
  }
  function results() {
    var host = document.getElementById('catalog-search-results');
    if (!host) return;
    var term = normalize(new URLSearchParams(root.location.search).get('q'));
    var input = document.querySelector('.search-box input'); input.value = term;
    document.getElementById('catalog-search-term').textContent = term ? '«' + term + '»' : '';
    document.getElementById('catalog-search-prompt').hidden = !!term;
    host.hidden = !term;
    if (!term) return;
    ['products', 'factories'].forEach(function (kind) {
      var grid = document.getElementById('catalog-' + kind);
      var status = document.getElementById('catalog-' + kind + '-status');
      var more = document.getElementById('catalog-' + kind + '-more');
      var offset = 0, busy = false;
      async function load() {
        if (busy) return;
        busy = true; more.disabled = true; status.hidden = false;
        status.textContent = t('fx_loading'); grid.setAttribute('aria-busy', 'true');
        try {
          await (root.SF_AUTH_READY || Promise.resolve());
          var page = await fetchPage(root.sb, kind, term, offset);
          page.rows.forEach(function (row) { grid.appendChild(card(row, kind)); });
          offset += page.rows.length;
          status.hidden = offset > 0 && !page.similar;
          status.textContent = offset ? (page.similar ? t('catalog_search_similar') : '') : t('no_results');
          more.hidden = !page.more; more.textContent = t('home_more_products');
        } catch (_) {
          status.hidden = false; status.textContent = t('catalog_search_failed');
          more.hidden = false; more.textContent = t('app_retry');
        } finally { busy = false; more.disabled = false; grid.setAttribute('aria-busy', 'false'); }
      }
      more.addEventListener('click', load);
      load();
    });
  }
  root.SFSiteSearch = { bind: bind, fetchPage: fetchPage, normalize: normalize, suggestions: suggestions, score: score };
  function start() { bind(); results(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})(window);
