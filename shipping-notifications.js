/* إشعارات محفوظة في الحساب؛ لا تُرسل رسائل بريد أو طلبات إلى شركة شحن. */
(function (root) {
  'use strict';
  var timer, link;
  async function refresh() {
    if (!root.SF_USER || document.hidden) return;
    try {
      var res = await root.sb.from('shipping_notifications').select('id', {count:'exact',head:true}).is('read_at',null);
      if (res.error) return;
      var count = res.count || 0;
      document.querySelectorAll('[data-shipping-nav]').forEach(function (el) {
        el.textContent = root.I18N.t('shipping_title') + (count ? ' (' + count + ')' : '');
      });
      if (count && !link) {
        link = document.createElement('a'); link.href = 'web-shipping.html'; link.setAttribute('role','status');
        link.style.cssText = 'position:fixed;bottom:80px;inset-inline-end:18px;z-index:90;background:#17663d;color:#fff;padding:10px 16px;border-radius:10px;font:600 14px Segoe UI,Tahoma,sans-serif;box-shadow:0 2px 12px #0002';
        document.body.appendChild(link);
      }
      if (link) { link.hidden = !count; link.textContent = root.I18N.t('shipping_updates') + ' (' + count + ')'; }
    } catch (_) { /* يبقى رابط الشحن متاحاً عند تعذر جلب العدد. */ }
  }
  root.SFShippingNotifications = {refresh:refresh};
  if (root.SF_AUTH_READY) root.SF_AUTH_READY.then(function () {
    refresh(); timer = setInterval(refresh,60000);
  });
  document.addEventListener('visibilitychange',refresh);
  root.addEventListener('pagehide',function () { clearInterval(timer); });
})(window);
