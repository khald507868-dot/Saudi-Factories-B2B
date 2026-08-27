/* Payment boundary. No provider is enabled by default.
 * Secrets must stay in Supabase Edge Function secrets, never in HTML or Git.
 */
(function (root) {
  "use strict";
  var provider = "manual";

  root.SFPayment = {
    provider: provider,
    isEnabled: function () {
      return provider === "moyasar" || provider === "tap";
    },
    start: function (order) {
      if (!order || !order.id) return Promise.reject(new Error("طلب غير صالح"));
      if (!this.isEnabled()) {
        return Promise.reject(new Error("الدفع الإلكتروني غير مفعّل بعد؛ اختر بوابة دفع أولًا"));
      }
      return Promise.reject(new Error("يجب تشغيل الدفع من Edge Function خادمية"));
    }
  };
}(window));
