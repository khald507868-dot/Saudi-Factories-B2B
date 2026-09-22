/* توافق الصفحات السابقة: اللغة والعملة الآن داخل المنتقي المشترك. */
(function (root) {
  'use strict';
  root.SFLang = {
    open: function () { if (root.SFCurrencyUI) root.SFCurrencyUI.open(); },
    close: function () { if (root.SFCurrencyUI) root.SFCurrencyUI.close(true); }
  };
})(window);
