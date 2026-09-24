(function (root) {
  'use strict';
  var PAGE_SIZE = 20;
  var pricingId = 0;
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
    var rated = Number.isFinite(avg) && avg >= 1 && avg <= 5 && Number.isInteger(count) && count > 0;
    if (!rated) avg = 0;
    var line = add(parent, 'div', '', 'offer-rating');
    var stars = add(line, 'span', '', 'offer-stars');
    stars.setAttribute('role', 'img'); stars.setAttribute('aria-label', rated ? avg.toFixed(1) + ' / 5' : t('reviews_none'));
    for (var i = 0; i < 5; i++) {
      var star = add(stars, 'span', rated ? '★' : '☆', 'offer-star');
      star.setAttribute('aria-hidden', 'true');
      var fill = add(star, 'span', '★', 'offer-star-fill');
      fill.style.width = (Math.max(0, Math.min(1, avg - i)) * 100) + '%';
    }
    if (rated) {
      var score = add(line, 'span', avg.toFixed(1) + ' (' + count + ')', 'offer-rating-score');
      score.setAttribute('aria-label', count === 1 ? t('reviews_count_one') : count + ' ' + t('reviews_count_many'));
    }
  }
  function priceRanges(product) {
    if (!product) return [];
    var base = Number(product.price), moq = Math.max(1, Number(product.moq) || 1);
    if (!Number.isFinite(base) || base <= 0 || !Number.isSafeInteger(moq)) return [];
    var tiers = (Array.isArray(product.tiers) ? product.tiers : []).filter(Boolean).map(function (tier) {
      return { min: Number(tier.min), max: tier.max == null || tier.max === '' ? Infinity : Number(tier.max), price: Number(tier.price) };
    }).filter(function (tier) {
      return Number.isSafeInteger(tier.min) && tier.min > 0 &&
        (tier.max === Infinity || Number.isSafeInteger(tier.max)) && tier.max >= tier.min &&
        Number.isFinite(tier.price) && tier.price > 0;
    }).sort(function (a, b) { return a.min - b.min; });
    var boundaries = [moq];
    tiers.forEach(function (tier) {
      if (tier.min > moq) boundaries.push(tier.min);
      if (Number.isFinite(tier.max) && tier.max >= moq) boundaries.push(tier.max + 1);
    });
    boundaries = Array.from(new Set(boundaries)).sort(function (a, b) { return a - b; });
    var ranges = [];
    for (var i = 0; i < boundaries.length; i++) {
      var min = boundaries[i], max = i + 1 < boundaries.length ? boundaries[i + 1] - 1 : null;
      var matches = tiers.filter(function (tier) { return min >= tier.min && min <= tier.max; });
      var chosen = matches[matches.length - 1];
      // Do not claim a price for ambiguous legacy tiers.
      if (chosen && matches.some(function (tier) { return tier.min === chosen.min && tier.price !== chosen.price; })) return [];
      var price = chosen ? chosen.price : base, previous = ranges[ranges.length - 1];
      if (previous && previous.price === price) previous.max = max;
      else ranges.push({ min: min, max: max, price: price });
    }
    return ranges;
  }
  async function loadPricing(client, items) {
    if (!items.length) return {};
    try {
      var result = await client.from('products').select('id,price,moq,tiers,factories!inner(status)')
        .eq('factories.status', 'approved').in('id', items.map(function (row) { return row.id; }));
      if (result.error) throw result.error;
      var map = {};
      (result.data || []).forEach(function (product) { map[String(product.id)] = priceRanges(product); });
      return map;
    } catch (_) { return {}; }
  }
  function card(row, summary, ranges) {
    var container = document.createElement('article'); container.className = 'catalog-card';
    var link = add(container, 'a', '', 'offer-product-link');
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
    var price = add(body, 'p', '', 'offer-price-summary');
    if (ranges && ranges.length) {
      var prices = ranges.map(function (tier) { return tier.price; });
      var low = Math.min.apply(null, prices), high = Math.max.apply(null, prices);
      if (low < high) {
        add(price, 'span', '', 'offers-unit-price').innerHTML = root.I18N.moneyRange(low.toFixed(2), high.toFixed(2));
      } else { money(price, low, 'offers-unit-price'); }
    } else { money(price, row.unit_price, 'offers-unit-price'); }
    add(price, 'span', ' ' + t('offers_per_unit'));
    if (!ranges || !ranges.length) add(body, 'p', quantity(row.min_quantity, row.max_quantity), 'offer-quantity');
    if (ranges && ranges.length) {
      var table = add(body, 'table', '', 'offer-pricing');
      table.id = 'offer-pricing-' + (++pricingId);
      add(table, 'caption', t('tier_pricing'));
      var header = add(add(table, 'thead'), 'tr');
      add(header, 'th', t('offer_quantity')).setAttribute('scope', 'col');
      add(header, 'th', t('offer_unit_price')).setAttribute('scope', 'col');
      var rows = add(table, 'tbody');
      var extraRows = [];
      ranges.forEach(function (tier, index) {
        var selected = tier.price === Number(row.unit_price) && Number(row.min_quantity) >= tier.min &&
          (tier.max == null || Number(row.min_quantity) <= tier.max);
        var tr = add(rows, 'tr', '', selected ? 'offer-pricing-selected' : '');
        add(tr, 'td', quantity(tier.min, tier.max));
        money(add(tr, 'td'), tier.price);
        if (index > 0) { tr.hidden = true; extraRows.push(tr); }
      });
      if (extraRows.length) {
        // A separate button keeps expanding prices from opening the product link.
        var toggle = add(container, 'button', t('home_more_products'), 'offer-pricing-toggle');
        toggle.type = 'button';
        toggle.setAttribute('aria-expanded', 'false');
        toggle.setAttribute('aria-controls', table.id);
        var expanded = false;
        toggle.addEventListener('click', function () {
          expanded = !expanded;
          extraRows.forEach(function (tr) { tr.hidden = !expanded; });
          toggle.setAttribute('aria-expanded', String(expanded));
          toggle.textContent = t(expanded ? 'currency_show_less' : 'home_more_products');
        });
      }
    } else {
      var reference = add(body, 'p', t('offers_compared_with') + ' ', 'offer-reference');
      money(reference, row.reference_price);
      add(reference, 'span', ' ' + t('offers_per_unit') + ' · ' + quantity(row.reference_min, row.reference_max));
    }
    return container;
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
        var details = await Promise.all([
          loadPricing(root.sb, page.items),
          Promise.resolve().then(function () {
            return page.items.length && root.SFReviews ? root.SFReviews.loadRatings(page.items.map(function (row) { return row.id; })) : {};
          }).catch(function () { return {}; })
        ]);
        var prices = details[0], ratings = details[1] || {};
        page.items.forEach(function (row) { grid.appendChild(card(row, ratings[String(row.id)], prices[String(row.id)])); }); offset += page.items.length;
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
