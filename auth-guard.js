// ============================================================
//  حارس الجلسة — يمنع فتح الصفحات الداخلية دون تسجيل دخول
//
//  يُحمَّل في <head> بعد supabase-config.js مباشرة.
//  الصفحات العامة لا تطرد الزائر، وصفحات الدخول والتسجيل
//  لا تحتاج هذا الحارس.
//
//  تطبيق الجوال مستقل داخل app_flutter؛ لذلك تخدم هذه النسخة
//  صفحات الموقع فقط وتعيد التوجيه دائمًا إلى web-login.html.
//
//  ملاحظة مهمة: هذا حارس تجربة استخدام، لا حماية بيانات.
//  الحماية الحقيقية في سياسات RLS داخل الخادم — فحتى لو
//  عطّل أحدهم هذا الملف، لن يقرأ بيانات ليست له.
// ============================================================

(function (global) {
  "use strict";

  /* تطبيق الجوال مستقل داخل app_flutter، وهذا الملف مخصص للموقع. */
  function currentPage() {
    var page = location.pathname.split("/").pop() || "index.html";
    return page + (location.search || "") + (location.hash || "");
  }

  function loginPage() {
    return "web-login.html";
  }

  function registerPage() {
    return "web-login.html";
  }

  /* تُملأ عند التحقق، وتستخدمها الصفحات بدل localStorage */
  global.SF_USER = null;

  /* ------------------------------------------------------------
     الصفحات العامة: يتصفحها الزائر دون تسجيل دخول — تماماً
     كما في علي بابا. الصفحة تضع قبل تحميل هذا الملف:
         <script>var SF_PUBLIC_PAGE = true;</script>
     فلا يطردها الحارس، لكنه يظل يقرأ الجلسة إن وُجدت
     ليعرف هل الزائر مسجّل أم لا.

     الشراء/المراسلة تظل محميّة: تُنادى sfRequireLogin() عندها.
     ------------------------------------------------------------ */
  var isPublic = global.SF_PUBLIC_PAGE === true;

  function redirect() {
    var here = currentPage();
    location.replace(loginPage() + "?next=" + encodeURIComponent(here));
  }

  /* يستدعيها أي زر يتطلب حساباً (شراء، سلة، مراسلة).
     ترجع true إذا كان مسجّلاً، وإلا حوّلته لصفحة التسجيل. */
  global.sfRequireLogin = function (nextPage) {
    if (global.SF_USER) return true;
    try { localStorage.setItem("sf_account_type", "individual"); } catch (e) {}
    var here = nextPage || currentPage();
    /* The query string must precede the fragment.  With #register?next=...
       the browser treats next as part of the fragment and the login page
       cannot read it from location.search. */
    location.href = registerPage() + "?next=" + encodeURIComponent(here) + "#register";
    return false;
  };

  var gateStyle = document.createElement("style");
  gateStyle.textContent = "html.sf-access-checking body{visibility:hidden}";
  document.head.appendChild(gateStyle);
  document.documentElement.classList.add("sf-access-checking");
  function reveal() { document.documentElement.classList.remove("sf-access-checking"); }
  global.SF_AUTH_READY = sb.auth.getSession().then(async function (res) {
    var session = res && res.data ? res.data.session : null;
    if (!session) {
      try { localStorage.setItem("sf_signed_in", "0"); } catch (_) {}
      if (!isPublic) redirect(); else reveal();
      return null;
    }
    var access = await global.SFAccountAccess.check();
    if (!global.SFAccountAccess.route(access, currentPage())) return null;
    global.SF_USER = access.user;
    global.SF_PROFILE = access.profile;
    try {
      localStorage.setItem("sf_signed_in", "1");
      localStorage.setItem("sf_account_type", access.profile.account_type);
    } catch (_) {}
    reveal();
    return access.user;
  }).catch(function () {
    global.SF_USER = null;
    global.SF_PROFILE = null;
    function failure() {
      var box = document.createElement("div");
      box.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#f4f8f5;display:grid;place-content:center;gap:20px;text-align:center;padding:24px";
      var message = document.createElement("p"); message.textContent = I18N.t("auth_check_failed");
      var retry = document.createElement("button"); retry.textContent = I18N.t("app_retry"); retry.onclick = function () { location.reload(); };
      box.append(message, retry); document.body.appendChild(box); reveal();
    }
    if (document.body) failure(); else document.addEventListener("DOMContentLoaded", failure, {once:true});
    return null;
  });

  /* تسجيل الخروج — تستدعيه أي صفحة */
  global.sfSignOut = function () {
    sb.auth.signOut().then(function () {
      try {
        localStorage.removeItem("sf_account_type");
        localStorage.removeItem("sf_account");
        localStorage.removeItem("sf_signed_in");
      } catch (e) {}
      /* إلى الواجهة الرئيسية زائراً لا إلى صفحة الدخول
         (بطلب المالك): من خرج لا يريد أن يدخل من
         فوره، والرئيسية صفحة عامّة (SF_PUBLIC_PAGE)
         تُفتح بلا حساب — فلا حلقة تحويل.

         والحارس يبقى يردّ إلى صفحة الدخول عند انتهاء
         الجلسة: ذاك من يريد البقاء فيُعاد إلى حيث كان. */
      location.replace("index.html");
    });
  };
})(window);
