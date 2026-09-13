/* Shared catalogue pricing for home and similar-product cards.
   Quantity-tier prices take precedence over the base unit price. */
(function (global) {
  "use strict";

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

  global.SFProductCard = { priceHTML: priceHTML };
})(window);
