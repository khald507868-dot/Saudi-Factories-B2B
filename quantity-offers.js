(function (root) {
  'use strict';
  var PAGE_SIZE = 20;
  var t = function (key) { return root.I18N.t(key); };
  function format(key, values) {
    return t(key).replace(/\{(\w+)\}/g, function (_, name) { return String(values[name]); });
  }
  function quantity(min, max) {
    return max == null ? format('offers_quantity_from', { min: min }) : format('offers_quantity_range', { min: min, max: max });
  }
  function add(parent, tag, text, className) {
    var el = document.createElement(tag); el.textContent = text || '';
    if (className) el.className = className;
    parent.appendChild(el); return el;
  }
  function money(parent, value, className) {
    var el = add(parent, 'span', '', className);
    // Only a finite server price enters the shared currency formatter's HTML.
    el.innerHTML = root.I18N.money(Number(value).toFixed(2)); return el;
  }
  function rating(parent, summary) {
    var avg = Number(summary && summary.avg), count = Number(summary && summary.count);
    if (!Number.isFinite(avg) || avg < 1 || avg > 5 || !Number.isInteger(count) || count < 1) return;
    var line = add(parent, 'div', '', 'offer-rating');
    var stars = add(line, 'span', '', 'offer-stars');
    stars.setAttribute('role', 'img'); stars.setAttribute('aria-label', avg.toFixed(1) + ' / 5');
    for (var i = 0; i < 5; i++) {
      var star = add(stars, 'span', '★', 'offer-star');
      star.setAttribute('aria-hidden', 'true');
      var fill = add(star, 'span', '★', 'offer-star-fill');
      fill.style.width = (Math.max(0, Math.min(1, avg - i)) * 100) + '%';
    }
    var score = add(line, 'span', avg.toFixed(1) + ' (' + count + ')', 'offer-rating-score');
    score.setAttribute('aria-label', count === 1 ? t('reviews_count_one') : count + ' ' + t('reviews_count_many'));
  }
  function card(row, summary) {
    var link = document.createElement('a'); link.className = 'catalog-card';
    link.href = 'web-product.html?id=' + encodeURIComponent(row.id);
    var visual = add(link, 'div', '', 'catalog-card-image');
    var url = [row.image].concat(Array.isArray(row.images) ? row.images : []).map(root.sfSafeHttpUrl).find(Boolean);
    if (url) {
      var img = document.createElement('img'); img.src = url; img.alt = ''; img.loading = 'lazy';
      img.addEventListener('error', function () { img.remove(); }); visual.appendChild(img);
    }
    add(visual, 'span', format('offers_saving', { percent: row.discount_percent }), 'offer-saving');
    var body = add(link, 'div', '', 'catalog-card-body');
    add(body, 'h3', row.name).setAttribute('data-sf-translate', '');
    add(body, 'p', row.factory_name, 'catalog-factory-name');
    rating(body, summary);
    var price = add(body, 'p'); money(price, row.unit_price, 'offers-unit-price');
    add(price, 'span', ' ' + t('offers_per_unit'));
    add(body, 'p', quantity(row.min_quantity, row.max_quantity), 'offer-quantity');
    var reference = add(body, 'p', t('offers_compared_with') + ' ', 'offer-reference');
    money(reference, row.reference_price);
    add(reference, 'span', ' ' + t('offers_per_unit') + ' · ' + quantity(row.reference_min, row.reference_max));
    return link;
  }
  async function fetchPage(client, id, offset) {
    var result = await client.rpc('get_promotion_quantity_offers', {
      p_promotion_id: id, p_offset: offset, p_limit: PAGE_SIZE
    });
    if (result.error) throw result.error;
    if (result.data != null && (!Array.isArray(result.data.items) || !result.data.items.every(function (row) {
      return Number.isFinite(Number(row.unit_price)) && Number(row.unit_price) > 0 &&
        Number.isFinite(Number(row.reference_price)) && Number(row.reference_price) > Number(row.unit_price);
    }))) throw new Error('Invalid offers response');
    return result.data;
  }
  function init() {
    var grid = document.getElementById('offers-grid'); if (!grid) return;
    var status = document.getElementById('offers-status'), more = document.getElementById('offers-more');
    var id = new URLSearchParams(root.location.search).get('promotion') || '';
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
      status.textContent = t('offers_unavailable'); return;
    }
    var offset = 0, busy = false;
    async function load() {
      if (busy) return;
      busy = true; more.disabled = true; grid.setAttribute('aria-busy', 'true');
      status.textContent = t('fx_loading');
      try {
        await (root.SF_AUTH_READY || Promise.resolve());
        var page = await fetchPage(root.sb, id, offset);
        if (!page) {
          grid.replaceChildren(); status.textContent = t('offers_unavailable'); more.hidden = true; return;
        }
        var ratings = {};
        if (page.items.length && root.SFReviews) {
          try { ratings = await root.SFReviews.loadRatings(page.items.map(function (row) { return row.id; })) || {}; }
          catch (_) { /* Products remain available if the rating service fails. */ }
        }
        page.items.forEach(function (row) { grid.appendChild(card(row, ratings[String(row.id)])); }); offset += page.items.length;
        status.textContent = offset ? '' : t('offers_empty');
        more.hidden = !page.has_more; more.textContent = t('home_more_products');
        if (root.SFTranslate) root.SFTranslate.translateAll(grid);
      } catch (_) {
        status.textContent = t('catalog_search_failed'); more.hidden = false; more.textContent = t('app_retry');
      } finally { busy = false; more.disabled = false; grid.setAttribute('aria-busy', 'false'); }
    }
    more.addEventListener('click', load);
    root.addEventListener('pageshow', function (event) {
      if (event.persisted && !busy) { offset = 0; grid.replaceChildren(); load(); }
    });
    load();
  }
  root.SFQuantityOffers = { fetchPage: fetchPage, card: card };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})(window);
