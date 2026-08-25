// ============================================================
//  حارس الجلسة — يمنع فتح الصفحات الداخلية دون تسجيل دخول
//
//  يُحمَّل في <head> بعد supabase-config.js مباشرة.
//  الصفحات العامة لا تحمّله: index و app-welcome و app-user-type
//  وصفحات الدخول والتسجيل في المسارين.
//
//  الوجهة عند الطرد ليست ثابتة: تُختار حسب مسار الصفحة
//  الحالية (web- أم app-) — انظر loginPage() و registerPage().
//
//  ملاحظة مهمة: هذا حارس تجربة استخدام، لا حماية بيانات.
//  الحماية الحقيقية في سياسات RLS داخل الخادم — فحتى لو
//  عطّل أحدهم هذا الملف، لن يقرأ بيانات ليست له.
// ============================================================

(function (global) {
  "use strict";

  /* ------------------------------------------------------------
     المشروع مساران منفصلان: صفحات `web-` للمتصفّح
     وصفحات `app-` للتطبيق. وهذا الملف مشترك بينهما،
     فلا تصلح وجهة ثابتة: زائر الموقع الذي تنتهي جلسته
     كان يُنقل إلى صفحة بتصميم الجوال في وسط شاشة عريضة.

     الحل: نقرأ اسم الصفحة الحالية ونبقى في مسارها.
     ملاحظة (تغيّرت 2026-08-25): index.html صارت صفحة المصانع
     أي مسار web — لأنها أول ما يراه الزائر عند فتح النطاق.
     ولأنها بلا بادئة web- فلا يكفي فحص البادئة وحدها؛
     وكذلك الجذر "" (فتح النطاق دون اسم ملف). أمّا شاشة
     بداية التطبيق فصارت app-index.html وتقع ضمن مسار التطبيق.
     ------------------------------------------------------------ */
  function currentPage() {
    return location.pathname.split("/").pop() || "index.html";
  }

  function isWebPath() {
    var p = currentPage();
    /* الجذر وـ index.html كلاهما صفحة المصانع — مسار web */
    if (p === "index.html" || p === "") return true;
    return p.indexOf("web-") === 0;
  }

  function loginPage() {
    /* مسار الموقع: حُذفت web-welcome.html، وصفحة الدخول الموحّدة
       بتبويبيها صارت الوجهة المباشرة. ومسار التطبيق بلا تغيير. */
    return isWebPath() ? "web-login.html" : "app-welcome.html";
  }

  function registerPage() {
    /* مسار الموقع: صفحة واحدة بتبويبين، والوسم ‎#register‎ يفتح تبويب التسجيل */
    return isWebPath() ? "web-login.html#register" : "app-register.html";
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
    location.href = registerPage() + "?next=" + encodeURIComponent(here);
    return false;
  };

  global.SF_AUTH_READY = sb.auth.getSession().then(function (res) {
    var session = res && res.data ? res.data.session : null;

    if (!session) {
      if (!isPublic) redirect();
      return null;
    }

    global.SF_USER = session.user;

    /* نوع الحساب من الخادم — لا من localStorage القابل للتزوير */
    return sb.from("profiles")
      .select("account_type, full_name, phone, email, is_admin, company_image")
      .eq("id", session.user.id).single()
      .then(function (p) {
        if (p.data) {
          global.SF_PROFILE = p.data;
          try {
            localStorage.setItem("sf_account_type", p.data.account_type);
          } catch (e) {}
        }
        return session.user;
      });
  }).catch(function () {
    /* انقطاع الشبكة: لا نطرد المستخدم، فقد تكون الجلسة سليمة */
    return null;
  });

  /* تسجيل الخروج — تستدعيه أي صفحة */
  global.sfSignOut = function () {
    sb.auth.signOut().then(function () {
      try {
        localStorage.removeItem("sf_account_type");
        localStorage.removeItem("sf_account");
      } catch (e) {}
      location.replace(loginPage());
    });
  };
})(window);
