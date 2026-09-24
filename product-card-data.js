/* Shared catalogue pricing for home and similar-product cards.
   Quantity-tier prices take precedence over the base unit price. */
(function (global) {
  "use strict";

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

  function escapeText(value) {
    return String(value).replace(/[&<>"']/g, function (character) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
  }

  function pricingHTML(ranges) {
    if (!ranges.length) return '';
    return '<div class="pc-pricing"><table><caption>' + escapeText(I18N.t('tier_pricing')) + '</caption>' +
      '<thead><tr><th scope="col">' + escapeText(I18N.t('offer_quantity')) + '</th><th scope="col">' + escapeText(I18N.t('offer_unit_price')) + '</th></tr></thead><tbody>' +
      ranges.map(function (tier, index) {
        var qty = tier.max == null ? tier.min + '+' : tier.min + '–' + tier.max;
        return '<tr' + (index ? ' data-pc-extra hidden' : '') + '><td><bdi>' + qty + '</bdi> ' + escapeText(I18N.t('tier_piece')) +
          '</td><td>' + I18N.money(tier.price.toFixed(2)) + '</td></tr>';
      }).join('') + '</tbody></table>' +
      (ranges.length > 1 ? '<button type="button" class="pc-pricing-toggle" aria-expanded="false">' + escapeText(I18N.t('home_more_products')) + '</button>' : '') + '</div>';
  }

  function bindPricingControls(scope, cardSelector) {
    if (scope.sfPricingBound) return;
    scope.sfPricingBound = true;
    scope.addEventListener('click', function (event) {
      var button = event.target.closest('.pc-pricing-toggle');
      if (!button) return;
      var cell = button.closest(cardSelector);
      if (!cell) return;
      event.preventDefault();
      var id = cell.getAttribute('data-product-id');
      var expanded = button.getAttribute('aria-expanded') !== 'true';
      scope.querySelectorAll(cardSelector + '[data-product-id]').forEach(function (item) {
        if (item.getAttribute('data-product-id') !== id) return;
        item.querySelectorAll('[data-pc-extra]').forEach(function (tr) { tr.hidden = !expanded; });
        var toggle = item.querySelector('.pc-pricing-toggle');
        if (toggle) {
          toggle.setAttribute('aria-expanded', String(expanded));
          toggle.textContent = I18N.t(expanded ? 'currency_show_less' : 'home_more_products');
        }
      });
    });
  }

  function trimNum(value) {
    return Number(value).toFixed(2).replace(/[.]00$/, "");
  }

  function priceHTML(product) {
    if (!product || !product.price) return "";
    var low = null;
    var high = null;
    (Array.isArray(product.tiers) ? product.tiers : []).forEach(function (tier) {
      if (!tier) return;
      var price = parseFloat(tier.price);
      var min = parseInt(tier.min, 10);
      if (!isFinite(price) || price <= 0 || !isFinite(min) || min < 1) return;
      if (low === null || price < low) low = price;
      if (high === null || price > high) high = price;
    });
    if (low !== null && high > low) {
      return global.I18N.moneyRange(trimNum(low), trimNum(high));
    }
    return global.I18N.money(low !== null ? trimNum(low) : product.price);
  }

  global.SFProductCard = { priceHTML: priceHTML, priceRanges: priceRanges, pricingHTML: pricingHTML, bindPricingControls: bindPricingControls };
})(window);
