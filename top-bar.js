/* ============================================================
   الشريط العلوي المشترك — SFTopBar
   ------------------------------------------------------------
   شريط البحث والحساب والسلة، وتحته شريط الفئات —
   كما في أمازون: موجود في صفحات المتجر والمنتج لا في
   الرئيسية وحدها (بطلب المالك، 2026-09-07).

   ملفّ مشترك لا نسخ في كلّ صفحة: الشريط 90 سطراً
   من الماركأب ونحو 500 من السكربت، وتكراره يعيد
   مأساة الشريط السفليّ المكرّر في عشرة ملفّات.

   الرئيسية تحتفظ بنسختها المكتوبة في الماركأب، فلا
   يُحقن فيها شيء — والملفّ يكتشف ذلك وحده.

   الترتيب ملزم: يُحمّل بعد i18n.js وsupabase-config.js،
   وينتظر DOMContentLoaded قبل الحقن.
   ============================================================ */
(function (global) {
  "use strict";

  var MARKUP = "    <div class=\"dt-bar\">\n      <!-- الشعار الكتابي: \"مصانع\" أخضر + \"السعودية\" أبيض، تحته خط متدرج -->\n      <a class=\"top-bar-logo\" href=\"index.html\" aria-label=\"الصفحة الرئيسية\">\n        <div class=\"wm-title\"><span class=\"w-green\">Saudi</span> <span class=\"w-dark\">Factories</span> <span class=\"w-b2b\">B2B</span></div>\n        <div class=\"wm-rule\"></div>\n      </a>\n\n      <div class=\"search-box\">\n        <svg viewBox=\"0 0 24 24\" fill=\"none\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n          <circle cx=\"11\" cy=\"11\" r=\"7\"></circle>\n          <line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line>\n        </svg>\n        <input type=\"text\" data-i18n-placeholder=\"search_placeholder\" placeholder=\"ابحث عن مصنع أو منتج...\">\n      </div>\n\n      <!-- أدوات الحساب — سطح المكتب فقط (مخفية على الجوال عبر desktop.css)\n           الترتيب كما في علي بابا: زر إنشاء الحساب، ثم الحساب، ثم السلة والرسائل -->\n      <div class=\"dt-actions\" id=\"dt-actions\">\n        <!-- يملؤه السكربت: زائر ← إنشاء حساب، مسجّل ← اسمه -->\n        <span id=\"dt-auth\"></span>\n\n        <a class=\"dt-icon\" href=\"web-account.html\" aria-label=\"حسابي\">\n          <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2\"></path><circle cx=\"12\" cy=\"7\" r=\"4\"></circle></svg>\n        </a>\n        <a class=\"dt-icon\" href=\"web-cart.html\" aria-label=\"السلة\">\n          <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"9\" cy=\"21\" r=\"1\"></circle><circle cx=\"20\" cy=\"21\" r=\"1\"></circle><path d=\"M1 1h4l2.7 13.4a2 2 0 0 0 2 1.6h9.7a2 2 0 0 0 2-1.6L23 6H6\"></path></svg>\n        </a>\n        <a class=\"dt-icon\" href=\"web-messages.html\" aria-label=\"الرسائل\">\n          <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M21 11.5a8.4 8.4 0 0 1-9 8.4 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.2a8.4 8.4 0 0 1-.9-3.8 8.4 8.4 0 0 1 8.4-9 8.4 8.4 0 0 1 8.6 8.5z\"></path></svg>\n        </a>\n\n        <!-- المساعدة والدعم: سمّاعة رأس مرسومة وسماً كبقية\n             الأيقونات — لا صور في المشروع. القوس هو طوق الرأس،\n             والمستطيلان هما وسادتا الأذنين. -->\n        <a class=\"dt-icon\" href=\"web-help.html\" aria-label=\"المساعدة والدعم\">\n          <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M4 14v-2a8 8 0 0 1 16 0v2\"></path><path d=\"M4 14h2a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z\"></path><path d=\"M20 14h-2a1 1 0 0 0-1 1v4a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1z\"></path></svg>\n        </a>\n\n        <!-- الموقع الجغرافي: دبّوس خريطة. تُفتح لوحة يلصق فيها\n             المستخدم رابط موقعه من قوقل ماب. المصنع تظهر نقطته\n             على الخريطة، والفرد يُحفظ موقعه للتوصيل وحده. -->\n        <button type=\"button\" class=\"dt-icon\" id=\"geo-btn\" aria-label=\"موقعي\" aria-haspopup=\"dialog\" aria-expanded=\"false\">\n          <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z\"></path><circle cx=\"12\" cy=\"10\" r=\"3\"></circle></svg>\n        </button>\n\n        <!-- كن مورّدًا: يملأ الفراغ في طرف الشريط، ويقود إلى\n             تبويب إنشاء الحساب في صفحة الدخول الموحّدة.\n             أيقونة مصنع مرسومة وسماً كبقية أيقونات الشريط. -->\n        <a class=\"dt-supplier\" href=\"web-supplier.html\" aria-label=\"كن مورّدًا\">\n          <svg viewBox=\"0 0 24 24\" fill=\"none\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n            <path d=\"M3 21h18\"></path>\n            <path d=\"M4 21V10l5 3V10l5 3V10l5 3v8\"></path>\n            <path d=\"M4 10 5 4h3l1 6\"></path>\n          </svg>\n          <span data-i18n=\"nav_become_supplier\">كن مورّدًا</span>\n        </a>\n      </div>\n    </div>\n\n    <!-- شريط الفئات — سطح المكتب فقط -->\n    <div class=\"dt-catbar\">\n      <div class=\"dt-catbar-inner\" id=\"dt-catbar-inner\">\n        <!-- زر الفئات: يفتح اللوحة عند مرور المؤشر -->\n        <div class=\"dt-catmenu\" id=\"dt-catmenu\">\n          <button type=\"button\" class=\"dt-catmenu-btn\" aria-haspopup=\"true\" aria-expanded=\"false\">\n            <svg viewBox=\"0 0 24 24\" stroke-linecap=\"round\"><line x1=\"3\" y1=\"6\" x2=\"21\" y2=\"6\"></line><line x1=\"3\" y1=\"12\" x2=\"21\" y2=\"12\"></line><line x1=\"3\" y1=\"18\" x2=\"21\" y2=\"18\"></line></svg>\n            <span data-i18n=\"nav_categories\">الفئات</span>\n          </button>\n\n          <!-- اللوحة: قائمة الفئات يميناً، ومنتجات الفئة يساراً -->\n          <div class=\"dt-catpanel\" id=\"dt-catpanel\">\n            <ul class=\"dt-catlist\" id=\"dt-catlist\"></ul>\n            <div class=\"dt-catpreview\" id=\"dt-catpreview\"></div>\n          </div>\n        </div>\n\n        <!-- الروابط داخل غلاف قابل للتمرير وحدها:\n             وضع overflow على .dt-catbar-inner يقصّ لوحة زر ☰ المنسدلة،\n             فالزر يبقى خارج الغلاف والروابط وحدها تُمرّر. -->\n        <div class=\"dt-catscroll\" id=\"dt-catscroll\"></div>\n\n        <!-- سهما التمرير: يظهران عند مرور المؤشر على الشريط،\n             والتمرير يبدأ بمجرد وقوف المؤشر عليهما دون ضغط -->\n        <button type=\"button\" class=\"dt-catnav left\" id=\"dt-catnav-left\" aria-label=\"المزيد من الفئات\">\n          <svg viewBox=\"0 0 24 24\"><polyline points=\"15 18 9 12 15 6\"></polyline></svg>\n        </button>\n        <button type=\"button\" class=\"dt-catnav right\" id=\"dt-catnav-right\" aria-label=\"المزيد من الفئات\">\n          <svg viewBox=\"0 0 24 24\"><polyline points=\"9 18 15 12 9 6\"></polyline></svg>\n        </button>\n      </div>\n    </div>";

  function inject() {
    /* الرئيسية تحمل الشريط في ماركأبها، فلا يُكرّر. */
    if (document.querySelector(".dt-bar")) return false;

    var host = document.createElement("div");
    host.innerHTML = MARKUP;

    /* قبل أوّل عنصر في body: الشريط أعلى الصفحة دائماً،
       وشعار الصفحة (.page-logo) يليه. */
    var first = document.body.firstElementChild;
    while (host.firstChild) {
      document.body.insertBefore(host.firstChild, first);
    }

    /* شعار الصفحة يُخفى حيث يُحقن الشريط: الشريط
       يحمل الشعار أصلاً، فيظهر مرّتين. والإخفاء هنا لا
       في ماركأب كلّ صفحة: من يضيف الشريط لصفحة جديدة
       لا يحتاج أن يتذكّر حذفه. */
    var logo = document.querySelector(".page-logo");
    if (logo) logo.hidden = true;

    return true;
  }

  function start() {
    if (!inject()) return;
    /* الترجمة بعد الحقن: applyTranslations جرت على
       DOMContentLoaded قبل أن يوجد الشريط. */
    if (global.I18N && I18N.applyTranslations) I18N.applyTranslations();
    wire();
  }

  function wire() {
  (function () {
    /* --- لوحة الفئات (☰) + روابط الشريط --- */
    var cats = (window.I18N && I18N.categories) ? I18N.categories : [];

    if (cats.length) {
      /* عمود الأسماء داخل اللوحة */
      var listEl = document.getElementById("dt-catlist");
      if (listEl) {
        listEl.innerHTML = cats.map(function (cat, i) {
          return '<li data-i="' + i + '"' + (i === 0 ? ' class="active"' : "") + '>' +
                 '<a href="web-factories.html?cat=' + encodeURIComponent(cat.en || "") + '">' +
                 I18N.categoryName(cat) + "</a></li>";
        }).join("");
      }

      /* المعاينة: تعرض الفئة التي يمرّ عليها المؤشر */
      var prev = document.getElementById("dt-catpreview");
      var thumbSvg = '<svg viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round">' +
                     '<rect x="3" y="3" width="18" height="18" rx="2"></rect>' +
                     '<circle cx="8.5" cy="8.5" r="1.5"></circle>' +
                     '<path d="M21 15l-5-5L5 21"></path></svg>';

      /* صور الفئات يضعها مدير الموقع من صفحة الإدارة.
         القراءة مفتوحة للجميع، والكتابة يرفضها الخادم لغير المدير،
         فهي ثابتة فعلاً لا بإخفاء زرّ في الواجهة. */
      var catImages = {};

      /* العنوان يتبع الفئة الممرّر عليها، والشبكة تعرض
         الفئات كلّها معاً — فالمقصود تصفّح الفئات لا عرض
         واحدة فقط (بطلب المالك). */
      function showPreview(i) {
        if (!prev || !cats[i]) return;
        var title = I18N.categoryName(cats[i]);

        var items = "";
        cats.forEach(function (cat) {
          var en = cat.en || "";
          var nm = I18N.categoryName(cat);
          var url = catImages[en];
          var media = url
            ? '<img src="' + url + '" alt="" loading="lazy">'
            : thumbSvg;

          items +=
            '<a class="dt-preview-item" href="web-factories.html?cat=' +
              encodeURIComponent(en) + '">' +
              '<div class="dt-preview-thumb">' + media + "</div>" +
              "<span>" + nm + "</span>" +
            "</a>";
        });

        prev.innerHTML = "<h4>" + title + "</h4>" +
                         '<div class="dt-preview-grid">' + items + "</div>";
      }

      /* تُقرأ مرّة واحدة ثم تُعاد المعاينة — اللوحة تظهر
         فوراً بالرمز النائب ولا تنتظر الشبكة. */
      if (window.sb) {
        sb.from("category_images").select("category_en, image_url")
          .then(function (r) {
            (r.data || []).forEach(function (row) {
              catImages[row.category_en] = row.image_url;
            });
            var active = document.querySelector("#dt-catlist li.active");
            showPreview(active ? parseInt(active.getAttribute("data-i"), 10) : 0);
          })
          .catch(function () {});
      }

      showPreview(0);

      if (listEl) {
        listEl.addEventListener("mouseover", function (e) {
          var li = e.target.closest("li[data-i]");
          if (!li) return;
          listEl.querySelectorAll("li").forEach(function (x) { x.classList.remove("active"); });
          li.classList.add("active");
          showPreview(parseInt(li.getAttribute("data-i"), 10));
        });
      }

      /* روابط الفئات المسطّحة بعد زر ☰ في نفس الشريط */
      /* الشريط يتنقل بهدوء بين الفئات تلقائياً، ويتوقف عند المرور
         عليه كي تبقى القراءة والضغط على أي فئة مريحة. */
      function setupCatScroll(box) {
        var L = document.getElementById("dt-catnav-left");
        var R = document.getElementById("dt-catnav-right");
        if (!L || !R) return;

        /* في RTL تكون scrollLeft سالبة في المتصفّحات الحديثة،
           فنقيس بالقيمة المطلقة ليعمل المنطق في الاتجاهين. */
        function maxScroll() { return box.scrollWidth - box.clientWidth; }

        /* آخر حالة مرسومة، لتجنّب لمس الـ DOM بلا داعٍ:
           sync يُنادى مع كل إطار أثناء الحركة التلقائية،
           وتبديل الأصناف يفرض إعادة حساب التخطيط في كل مرة. */
        var lastSync = "";

        function sync() {
          var pos = Math.abs(box.scrollLeft);
          var max = maxScroll();
          var atStart = pos <= 1;
          var atEnd = pos >= max - 1;
          var rtl = document.documentElement.getAttribute("dir") === "rtl";

          var stateKey = (atStart ? "1" : "0") + (atEnd ? "1" : "0") +
                         (rtl ? "1" : "0") + (max > 0 ? "1" : "0");
          if (stateKey === lastSync) return;
          lastSync = stateKey;

          /* السهم الذي يمضي إلى المزيد يقع يساراً في العربية
             ويميناً في الإنجليزية — مرآة تتبع اتجاه القراءة. */
          var moreEl = rtl ? L : R;
          var backEl = rtl ? R : L;
          moreEl.classList.toggle("is-active", !atEnd && max > 0);
          backEl.classList.toggle("is-active", !atStart && max > 0);
        }

        /* اتجاه الخطوة: موجبة تمضي للأمام في الاتجاهين معاً.
           المسافة وسيط: قفزة الضغط واسعة، وخطوة التمرير
           التلقائي صغيرة ومتكرّرة لتكون الحركة ناعمة بطيئة. */
        function step(el, forward, dist) {
          var rtl = document.documentElement.getAttribute("dir") === "rtl";
          var sign = rtl ? -1 : 1;
          var d = dist || 240;
          box.scrollLeft += sign * (forward ? d : -d);
        }

        function hold(el, forward) {
          var timer = null;
          el.addEventListener("mouseenter", function () {
            if (timer) return;
            /* smooth يُلغى أثناء الوقوف: كل خطوة صغيرة تبدأ
               حركة انتقالية فتتداخل مع التي قبلها وتتقطّع */
            box.style.scrollBehavior = "auto";
            /* ٤ بكسل كل ٢٠ms: أبطأ بكثير ممّا كان (٢٤٠ كل ٩٠ms) */
            timer = setInterval(function () { step(el, forward, 4); }, 20);
          });
          function stop() {
            if (timer) { clearInterval(timer); timer = null; }
          }
          el.addEventListener("mouseleave", function () {
            stop();
            box.style.scrollBehavior = "";
          });
          /* قفزة النقر تبقى ناعمة: تُعاد smooth صراحةً لأنّ
             الحركة التلقائية تتركه auto. ويُستأنف الإلغاء
             تلقائياً في أوّل إطار بعد انتهاء الوقوف. */
          el.addEventListener("click", function () {
            box.style.scrollBehavior = "smooth";
            step(el, forward);
          });
          box.addEventListener("scroll", sync);
          return stop;
        }

        var rtlNow = document.documentElement.getAttribute("dir") === "rtl";
        hold(rtlNow ? L : R, true);
        hold(rtlNow ? R : L, false);

        /* نحو 80 بكسل في الثانية، محسوبة بالزمن لا بالإطار
           (كانت 50ms ثم 30ms، فأُسرعت مرّتين بطلب المالك).

           16ms هو حدّ السرعة المفيد: يوافق معدّل تحديث الشاشة
           (60 إطاراً/ث)، وما دونه لا يزيد النعومة بل يهدر
           المعالج في خطوات لا تُرسم.

           بلغنا حدّ الفاصل، فصار التسريع بالخطوة: العدد الصحيح
           مقصود لأن بعض المتصفحات تتجاهل كسور البكسل عند فتح
           الصفحة من الملفات، وخطوة أكبر تجعل الحركة متقطّعة. */
        var autoPaused = false;
        var autoDirection = 1;
        /* الموضع الحقيقي يُحفظ بكسره هنا، ويُسند إلى
           scrollLeft مدوّراً. ولولا ذلك لضاع الكسر في كل إطار
           وعادت الحركة إلى قفزات بكسل كامل. */
        var autoPos = null;
        var lastFrame = 0;

        /* السرعة بالبكسل في الثانية، لا بالبكسل في الإطار:
           فتتساوى الحركة على شاشة 60هرتز وشاشة 144هرتز. */
        var AUTO_SPEED = 80;

        function autoMove(now) {
          requestAnimationFrame(autoMove);

          var max = maxScroll();
          var rtl = document.documentElement.getAttribute("dir") === "rtl";

          /* التوقّف يُسقِط الطابع الزمني، وإلا قفز الشريط
             دفعةً واحدة بقدر مدّة التوقّف عند استئنافه. */
          if (autoPaused || document.hidden || max <= 1) {
            lastFrame = 0;
            autoPos = null;
            return;
          }

          if (autoPos === null) autoPos = Math.abs(box.scrollLeft);
          if (!lastFrame) { lastFrame = now; return; }

          /* الشريط يحمل scroll-behavior: smooth في desktop.css.
             ومع إسناد كل إطار يبدأ ذلك حركة انتقالية
             جديدة تلغي سابقتها قبل أن تكتمل، فيجمد الشريط
             مكانه تماماً. يُلغى هنا ويُعاد للنقر وحده. */
          if (box.style.scrollBehavior !== "auto") box.style.scrollBehavior = "auto";

          /* الزمن المنقضي يُقيّد بـ 100ms: إطار متأخّر بعد
             تعثّر لا يدفع الشريط قفزة مفاجئة. */
          var dt = Math.min(now - lastFrame, 100);
          lastFrame = now;

          autoPos += autoDirection * AUTO_SPEED * dt / 1000;

          if (autoPos >= max) { autoPos = max; autoDirection = -1; }
          else if (autoPos <= 0) { autoPos = 0; autoDirection = 1; }

          /* بلا تدوير: scrollLeft يقبل الكسور في المتصفّحات
             الحديثة، والتدوير يجعل الموضع يثبت إطارين ثمّ
             يقفز بكسلاً كاملاً — وهذا الارتجاج المتبقّي.
             ومن لا يدعمها يدوّر داخلياً، فلا يسوء عنده شيء. */
          box.scrollLeft = (rtl ? -1 : 1) * autoPos;
        }

        /* يشمل المساحة كاملةً والأسهم، ولا يتوقف الشريط عند المرور
           على عنصر داخلي فقط ثم يعود للتحرك أثناء اختيار الفئة. */
        var pauseArea = box.closest(".dt-catbar-inner") || box;
        pauseArea.addEventListener("mouseenter", function () { autoPaused = true; });
        pauseArea.addEventListener("mouseleave", function () { autoPaused = false; });
        /* requestAnimationFrame بدل setInterval: يتزامن مع رسم
           المتصفّح بدل أن يخمّن التوقيت. setInterval لا يضمن
           الفاصل المطلوب — يتأخّر تحت الحمل ثم يتراكم، فتقع
           خطوتان في إطار واحد ولا شيء في التالي — وهذا هو
           التقطّع الذي يُرى. وهو يتوقّف تلقائياً في التبويب
           المخفي، فلا يهدر البطّارية. */
        requestAnimationFrame(autoMove);

        /* عجلة الفأرة الرأسية تُحوّل إلى تمرير أفقي */
        box.addEventListener("wheel", function (e) {
          if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
          e.preventDefault();
          box.scrollLeft += (document.documentElement.getAttribute("dir") === "rtl" ? -1 : 1) * e.deltaY;
        }, { passive: false });

        window.addEventListener("resize", sync);
        sync();
      }

      /* الفئات كلها لا أول ثمانٍ: الشريط يُمرّر أفقياً
         فيظهر الباقي عند التمرير إلى آخر اليسار. */
      var bar = document.getElementById("dt-catscroll");
      if (bar) {
        var html = "";
        cats.forEach(function (cat) {
          html += '<a href="web-factories.html?cat=' + encodeURIComponent(cat.en || "") + '">' +
                  I18N.categoryName(cat) + "</a>";
        });
        bar.innerHTML = html;
        setupCatScroll(bar);
      }
    }

    /* حالة الحساب: زائر ← دخول + إنشاء حساب، مسجّل ← حسابي */
    var slot = document.getElementById("dt-auth");
    if (!slot) return;

    /* الزر يتبع حالة الجلسة: زائر ← "تسجيل دخول"، ومسجّل ←
       لا زر. كان ثابتاً على "تسجيل دخول" في الحالتين، فيظهر
       لمن سجّل دخوله وهو ما لا معنى له.

       الجلسة تصل بعد رسم الصفحة، فنرسم زر الدخول أولاً ثم
       نصحّحه حين تجهز SF_AUTH_READY — بدل صفحة فارغة أو وميض.
       النص من I18N ليتبع اللغة المختارة كبقية الصفحة. */
    function paintAuth(signedIn) {
      /* المسجّل لا يرى زراً هنا: تسجيل الخروج موجود في
         الإعدادات، ووضعه في الشريط تكرار. والوصول للحساب
         عبر أيقونة الحساب المجاورة. */
      slot.innerHTML = signedIn ? "" :
        '<a class="dt-btn primary" href="web-login.html" data-i18n="splash_login_btn">' +
        I18N.t("splash_login_btn") + "</a>";
      slot.style.visibility = "";
    }

    /* ===== لا وميض عند التحديث =====
       الجلسة تصل من الشبكة بعد رسم الصفحة، فرسم زر "تسجيل دخول"
       افتراضياً كان يُظهره للمسجّل جزءاً من الثانية ثم يختفي.

       الحل ثلاث حالات لا حالتان:
         • العلامة تقول "مسجّل"  ← لا نرسم زراً إطلاقاً.
         • العلامة تقول "زائر"   ← نرسم الزر فوراً بلا انتظار.
         • لا علامة (أول زيارة) ← نخفي المكان حتى يصل الجواب،
           فلا يرى أحد زراً يظهر ثم يختفي.

       العلامة للعرض فقط؛ SF_AUTH_READY تصحّحها دائماً بعدها. */
    var guess = null;
    try { guess = localStorage.getItem("sf_signed_in"); } catch (e) {}

    if (guess === "1") {
      paintAuth(true);
    } else if (guess === null) {
      slot.innerHTML = "";
      slot.style.visibility = "hidden";
    } else {
      paintAuth(false);
    }

    if (window.SF_AUTH_READY) {
      /* catch أيضاً: لو انقطعت الشبكة في أوّل زيارة بقي المكان
         مخفياً بلا زر إطلاقاً. الفشل يعني "لا جلسة"، فيُرسم
         زر الدخول — وهو التصرّف الآمن. */
      SF_AUTH_READY.then(function () {
        paintAuth(!!window.SF_USER);
      }).catch(function () {
        paintAuth(false);
      });
    } else {
      /* الحارس غائب: لا ننتظر جواباً لن يأتي */
      paintAuth(false);
    }

    /* زر "كن مورّداً": دعوة للمصانع كي تسجّل — فلا معنى
       لعرضه لمن سجّل دخوله أصلاً كمورّد. يعود بعد تسجيل
       الخروج من الإعدادات لأن sfSignOut تمحو الجلسة.

       المصدر هو account_type القادم من جدول profiles عبر
       الحارس، لا localStorage القابل للتزوير. ولأن الجلسة
       تصل بعد رسم الصفحة، نخفي الزر مبكّراً إن كان
       localStorage يقول "factory" لمنع الوميض، ثم نصحّح
       القرار من الخادم حين تجهز SF_AUTH_READY. */
    var supplierCta = document.querySelector(".dt-supplier");
    if (supplierCta) {
      function showSupplierCta(show) {
        supplierCta.style.display = show ? "" : "none";
      }

      var cachedType = "";
      try { cachedType = localStorage.getItem("sf_account_type") || ""; } catch (e) {}
      showSupplierCta(cachedType !== "factory");

      if (window.SF_AUTH_READY) {
        SF_AUTH_READY.then(function () {
          var type = window.SF_PROFILE ? window.SF_PROFILE.account_type : "";
          showSupplierCta(type !== "factory");
        });
      }
    }
  })();

  (function () {
    var btn = document.getElementById("geo-btn");
    var overlay = document.getElementById("geo-overlay");
    if (!btn || !overlay) return;

    var input = document.getElementById("geo-input");
    var msg = document.getElementById("geo-msg");
    var saveBtn = document.getElementById("geo-save");
    var closeBtn = document.getElementById("geo-close");

    function say(text, ok) {
      msg.textContent = text;
      msg.classList.toggle("ok", !!ok);
      msg.hidden = !text;
    }

    function open() {
      overlay.hidden = false;
      btn.setAttribute("aria-expanded", "true");
      document.body.style.overflow = "hidden";
      say("", false);

      /* الموقع المحفوظ يظهر في الحقل ليعدّله لا ليعيد كتابته. */
      if (window.SFGeo && window.SF_USER) {
        SFGeo.loadMine().then(function (row) {
          if (row && row.map_url) input.value = row.map_url;
        }).catch(function () {});
      }
      input.focus();
    }

    function close() {
      overlay.hidden = true;
      btn.setAttribute("aria-expanded", "false");
      document.body.style.overflow = "";
    }

    btn.addEventListener("click", open);
    closeBtn.addEventListener("click", close);
    overlay.addEventListener("click", function (e) {
      if (e.target === overlay) close();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !overlay.hidden) close();
    });

    /* ===== الموقع الحالي من الجهاز =====
       يعطي إحداثيات مباشرة، فلا حاجة إلى رابط أصلاً. يمرّ على
       SFGeo.save نفسها ليبقى مسار الحفظ واحداً. */
    var gpsBtn = document.getElementById("geo-gps");
    if (gpsBtn) {
      gpsBtn.addEventListener("click", function () {
        if (!window.SF_USER) {
          say(I18N.t("login_required_action"), false);
          return;
        }
        if (!navigator.geolocation) {
          say(I18N.t("geo_unavailable"), false);
          return;
        }

        gpsBtn.disabled = true;
        say(I18N.t("geo_locating"), true);

        navigator.geolocation.getCurrentPosition(function (pos) {
          /* يُبنى رابط قوقل قياسي من الإحداثيات، فيُحفظ
             map_url صالحاً للفتح كما لو لصقه المستخدم. */
          var lat = pos.coords.latitude, lng = pos.coords.longitude;
          var url = "https://www.google.com/maps/@" + lat + "," + lng + ",17z";
          input.value = url;

          SFGeo.save(url).then(function () {
            say(I18N.t("geo_saved"), true);
            if (SFGeo.isFactoryAccount()) drawPins();
            window.setTimeout(close, 1200);
          }).catch(function (err) {
            say((err && err.message) || I18N.t("geo_bad_link"), false);
          }).then(function () {
            gpsBtn.disabled = false;
          });
        }, function (err) {
          gpsBtn.disabled = false;
          say(err && err.code === 1 ? I18N.t("geo_denied")
                                    : I18N.t("geo_unavailable"), false);
        }, { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 });
      });
    }

    saveBtn.addEventListener("click", function () {
      if (!window.SF_USER) {
        say(I18N.t("login_required_action") || "\u064a\u062c\u0628 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644", false);
        return;
      }
      if (!window.SFGeo) return;

      saveBtn.disabled = true;
      say("", false);

      SFGeo.save(input.value).then(function (point) {
        say(I18N.t("geo_saved"), true);
        /* نقطة المصنع تظهر فوراً بلا إعادة تحميل. */
        if (SFGeo.isFactoryAccount()) drawPins();
        window.setTimeout(close, 1200);
      }).catch(function (err) {
        say((err && err.message) || I18N.t("geo_bad_link"), false);
      }).then(function () {
        saveBtn.disabled = false;
      });
    });

    /* ===== رسم نقاط المصانع =====
       المعايرة: حدود المملكة من regions-geo.js مقابل حدود
       رسم الخريطة (viewBox بلا الهامش). الإسقاط Mercator في
       المحور الرأسي كالخرائط الحقيقية، وخطّي في الأفقي. */
    var LAT_MIN = 16.3795, LAT_MAX = 32.1541;
    var LON_MIN = 34.4944, LON_MAX = 55.6667;
    var MAP_W = 730, MAP_H = 600;

    function mercY(lat) {
      var s = Math.sin(lat * Math.PI / 180);
      return Math.log((1 + s) / (1 - s)) / 2;
    }

    var Y_TOP = mercY(LAT_MAX), Y_BOTTOM = mercY(LAT_MIN);

    function projectPoint(lat, lon) {
      return {
        x: (lon - LON_MIN) / (LON_MAX - LON_MIN) * MAP_W,
        y: (Y_TOP - mercY(lat)) / (Y_TOP - Y_BOTTOM) * MAP_H
      };
    }

    function drawPins() {
      var svg = document.querySelector("svg.ksa-map");
      if (!svg || !window.SFGeo) return;

      SFGeo.loadFactoryPins().then(function (rows) {
        var old = svg.querySelector("#factory-pins");
        if (old) old.parentNode.removeChild(old);
        if (!rows.length) return;

        var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
        g.setAttribute("id", "factory-pins");

        rows.forEach(function (row) {
          var p = projectPoint(Number(row.lat), Number(row.lng));
          if (!isFinite(p.x) || !isFinite(p.y)) return;

          var c = document.createElementNS("http://www.w3.org/2000/svg", "circle");
          c.setAttribute("class", "factory-pin");
          c.setAttribute("cx", p.x.toFixed(1));
          c.setAttribute("cy", p.y.toFixed(1));
          c.setAttribute("r", "7");

          var title = document.createElementNS("http://www.w3.org/2000/svg", "title");
          title.textContent = row.name || "";
          c.appendChild(title);

          c.addEventListener("click", function () {
            window.location.href = "web-factory.html?id=" + encodeURIComponent(row.id);
          });

          g.appendChild(c);
        });

        svg.appendChild(g);
      }).catch(function () {});
    }

    /* النقاط عامة: تُرسم للزائر كما للمسجّل. */
    if (window.SF_AUTH_READY) {
      SF_AUTH_READY.then(drawPins).catch(drawPins);
    } else {
      drawPins();
    }
  })();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }

  global.SFTopBar = { inject: inject };
})(window);
