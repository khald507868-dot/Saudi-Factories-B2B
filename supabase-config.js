// ============================================================
//  إعدادات الاتصال بـ Supabase
//  يُحمَّل في <head> قبل أي سكربت يستخدم قاعدة البيانات.
//
//  المفتاح هنا عام ومقصود كشفه — الحماية الحقيقية
//  من سياسات RLS في schema.sql، لا من إخفاء المفتاح.
//  لا تضع مفتاح sb_secret_ هنا إطلاقًا.
// ============================================================

var SUPABASE_URL = "https://yhofxryhlrrwzztfowpa.supabase.co";
var SUPABASE_KEY = "sb_publishable_ur0SfOOGa552ZvQf2icdfg_6xVpw-yM";

// عميل مشترك لكل الصفحات
function sfSafeHttpUrl(value) {
  try {
    var raw = String(value || '').trim();
    if (!raw) return '';
    /* location.origin is the literal string "null" under file:// and is not
       a valid URL base.  location.href supports both local development and
       hosted pages; the protocol allow-list below still rejects file/data. */
    var url = new URL(raw, window.location.href);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return '';
    return url.href;
  } catch (e) {
    return '';
  }
}

/* Return only to a page in this static web bundle after authentication.
   Rebuilding the target from its filename also prevents directory traversal
   and keeps file:// development and hosted deployments behaving the same. */
function sfAuthReturnTarget(fallback) {
  var safeFallback = fallback || "index.html";
  try {
    var raw = new URLSearchParams(window.location.search).get("next");
    if (!raw) return safeFallback;

    var target = new URL(raw, window.location.href);
    if (target.protocol !== window.location.protocol || target.host !== window.location.host) {
      return safeFallback;
    }

    var page = target.pathname.split("/").pop() || "";
    if (!/^(?:index|web-[a-z0-9-]+)\.html$/i.test(page) ||
        /^(?:web-login|web-supplier|web-reset)\.html$/i.test(page)) {
      return safeFallback;
    }
    return page + target.search + target.hash;
  } catch (e) {
    return safeFallback;
  }
}

var sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
