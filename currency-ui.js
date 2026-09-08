/* ===== واجهة منتقي العملة =====
   لوحة منسدلة تحت زرّها مباشرة، على شكل منتقي اللغة نفسه
   (بطلب المالك) لا ورقةً سفليّة: نفس المربّع 40×40، ونفس
   اللوحة والسهم وأزرار الاختيار الدائرية، ونفس زرّ «عملات
   أخرى» لأنّ الثلاثين لا تتّسع لها لوحة منسدلة.

   الاختيار يعيد تحميل الصفحة كما تفعل اللغة تماماً: أرخص
   من إعادة رسم كلّ سعر في كلّ صفحة، وأضمن ألّا يبقى سعر
   قديم في ركن منسيّ. */
(function (global) {
  "use strict";

  var doc = global.document;
  if (!doc) return;

  function t(key, fallback) {
    if (global.I18N && typeof I18N.t === "function") {
      var v = I18N.t(key);
      if (v && v !== key) return v;
    }
    return fallback;
  }

  /* المعروضة أوّلاً: الريال ثمّ أكثرها استعمالاً في تجارة
     المملكة. والبقيّة خلف «عملات أخرى». */
  var PRIMARY = ["SAR", "USD", "EUR", "AED"];

  function injectStyles() {
    if (doc.getElementById("sf-cur-styles")) return;
    var css = [
      /* مطابق لـ .dt-icon وزرّ اللغة: مربّع 40×40 بنفس الإطار */
      ".sf-cur-wrap{position:relative;display:inline-flex}",
      ".sf-cur-btn{width:40px;height:40px;border:1px solid #c7dfce;background:#f4f8f5;",
      "border-radius:10px;display:flex;align-items:center;justify-content:center;",
      "cursor:pointer;position:relative;padding:0;font:inherit;",
      "box-shadow:0 2px 6px rgba(4,54,27,0.04);",
      "transition:background .18s ease,border-color .18s ease,box-shadow .18s ease}",
      ".sf-cur-btn:hover,.sf-cur-btn.open{background:#e6f2ea;border-color:#8fbe9e;",
      "box-shadow:0 4px 10px rgba(4,54,27,0.10)}",
      ".sf-cur-btn svg{width:22px;height:22px;stroke:#04361b;fill:none;stroke-width:1.9}",

      /* لوحة منسدلة تحت الزر مباشرة، لا ورقة سفلية */
      ".sf-cur-panel{position:absolute;top:calc(100% + 10px);z-index:200;",
      "background:#fff;border-radius:10px;width:290px;",
      "box-shadow:0 6px 24px rgba(4,54,27,0.18);border:1px solid #e2ebe5;",
      "padding:14px 0 10px;opacity:0;visibility:hidden;transform:translateY(-6px);",
      "transition:opacity .15s ease,transform .15s ease,visibility .15s}",
      ".sf-cur-panel.open{opacity:1;visibility:visible;transform:translateY(0)}",

      /* اللوحة تتبع الزر: من اليمين في العربية ومن اليسار في
         الإنجليزية — مرآة لا ترتيب ثابت، فلها نظير ltr */
      ".sf-cur-panel{right:0}",
      'html[dir="ltr"] .sf-cur-panel{right:auto;left:0}',

      /* سهم صغير يربط اللوحة بالزر */
      ".sf-cur-panel::before{content:'';position:absolute;top:-7px;",
      "width:12px;height:12px;background:#fff;border-inline-start:1px solid #e2ebe5;",
      "border-top:1px solid #e2ebe5;transform:rotate(45deg);right:14px}",
      'html[dir="ltr"] .sf-cur-panel::before{right:auto;left:14px}',

      ".sf-cur-title{font-size:14.5px;font-weight:700;color:#12331d;",
      "padding:0 16px 6px;margin:0}",

      /* تنبيه المحاسبة بالريال تحت العنوان مباشرة */
      ".sf-cur-note{font-size:11.5px;color:#5c6b62;line-height:1.5;",
      "padding:0 16px 10px;margin:0}",

      ".sf-cur-list{max-height:300px;overflow-y:auto}",

      /* صف العملة: زر اختيار دائري ثم الرمز والاسم */
      ".sf-cur-item{display:flex;align-items:center;gap:10px;width:100%;border:0;",
      "background:none;font:inherit;font-size:13.5px;text-align:start;",
      "padding:9px 16px;cursor:pointer;color:#12331d}",
      ".sf-cur-item:hover{background:#f2f8f4}",
      ".sf-cur-item + .sf-cur-item{border-top:1px solid #f0f4f1}",
      ".sf-cur-item.selected{font-weight:700}",

      ".sf-cur-radio{width:16px;height:16px;border-radius:50%;border:1.5px solid #9db3a5;",
      "flex-shrink:0;position:relative;box-sizing:border-box}",
      ".sf-cur-item.selected .sf-cur-radio{border-color:#1f6b42}",
      ".sf-cur-item.selected .sf-cur-radio::after{content:'';position:absolute;",
      "inset:3px;border-radius:50%;background:#1f6b42}",

      ".sf-cur-code{font-weight:700;color:#1f6b42;min-width:38px}",
      ".sf-cur-name{flex:1}",
      ".sf-cur-symbol{color:#5c6b62}",

      ".sf-cur-more{display:block;width:100%;border:0;background:none;font:inherit;",
      "font-size:13px;color:#1f6b42;cursor:pointer;padding:10px 16px 2px;",
      "text-align:start;border-top:1px solid #eef2ef;margin-top:6px}",
      ".sf-cur-more:hover{text-decoration:underline}",

      "@media (prefers-reduced-motion: reduce){.sf-cur-panel{transition:none}}"
    ].join("");
    var st = doc.createElement("style");
    st.id = "sf-cur-styles";
    st.textContent = css;
    doc.head.appendChild(st);
  }

  var panel = null, listEl = null, moreBtn = null, theBtn = null;
  var expanded = false;

  function buildPanel(wrap) {
    if (panel) return;
    panel = doc.createElement("div");
    panel.className = "sf-cur-panel";

    var title = doc.createElement("p");
    title.className = "sf-cur-title";
    title.textContent = t("currency_pick", "اختر العملة");

    /* تنبيه صريح: العرض يتحوّل والمحاسبة بالريال. إخفاؤه
       يجعل المشتري يظنّ أنّه سيدفع بعملته. */
    var note = doc.createElement("p");
    note.className = "sf-cur-note";
    note.textContent = t("currency_note",
      "الأسعار تُعرض بالعملة المختارة للاطّلاع، والمحاسبة تتمّ بالريال السعودي.");

    listEl = doc.createElement("div");
    listEl.className = "sf-cur-list";

    moreBtn = doc.createElement("button");
    moreBtn.type = "button";
    moreBtn.className = "sf-cur-more";
    moreBtn.addEventListener("click", function () {
      expanded = !expanded;
      render();
    });

    panel.appendChild(title);
    panel.appendChild(note);
    panel.appendChild(listEl);
    panel.appendChild(moreBtn);
    wrap.appendChild(panel);
  }

  function render() {
    if (!global.SFCurrency || !listEl) return;
    var current = SFCurrency.getCode();
    var lang = (global.I18N && I18N.getLang && I18N.getLang()) || "ar";
    listEl.innerHTML = "";

    var all = SFCurrency.list();
    var shown = expanded ? all : all.filter(function (c) {
      /* عملة المستخدم تظهر دائماً ولو لم تكن من الرئيسة */
      return PRIMARY.indexOf(c.code) !== -1 || c.code === current;
    });

    shown.forEach(function (c) {
      var btn = doc.createElement("button");
      btn.type = "button";
      btn.className = "sf-cur-item" + (c.code === current ? " selected" : "");

      var radio = doc.createElement("span");
      radio.className = "sf-cur-radio";

      var code = doc.createElement("span");
      code.className = "sf-cur-code";
      code.textContent = c.code;

      var name = doc.createElement("span");
      name.className = "sf-cur-name";
      name.textContent = lang === "ar" ? c.ar : c.en;

      var sym = doc.createElement("span");
      sym.className = "sf-cur-symbol";
      sym.textContent = c.sym;

      btn.appendChild(radio);
      btn.appendChild(code);
      btn.appendChild(name);
      btn.appendChild(sym);

      btn.addEventListener("click", function () {
        if (c.code === current) { close(); return; }
        SFCurrency.setCode(c.code);
        /* إعادة تحميل كاملة كما في تغيير اللغة */
        global.location.reload();
      });

      listEl.appendChild(btn);
    });

    moreBtn.textContent = expanded
      ? t("currency_show_less", "عرض أقل")
      : t("currency_more", "عملات أخرى");
  }

  function open() {
    render();
    panel.classList.add("open");
    if (theBtn) theBtn.classList.add("open");
  }

  function close() {
    if (!panel) return;
    panel.classList.remove("open");
    if (theBtn) theBtn.classList.remove("open");
  }

  function toggle() {
    if (!panel) return;
    if (panel.classList.contains("open")) close();
    else open();
  }

  /* الأيقونة: عملة معدنية فيها علامة عملة — وليست كرةً
     أرضية: الكرة تعني اللغة في عرف المواقع، فتركها هنا
     يُلبِس بزرّ اللغة المجاور. مرسومة وسماً كبقيّة
     أيقونات الشريط، فلا صور في المشروع. */
  function makeButton() {
    var btn = doc.createElement("button");
    btn.type = "button";
    btn.className = "sf-cur-btn";
    btn.id = "sf-cur-btn";
    var code = global.SFCurrency ? SFCurrency.getCode() : "SAR";
    btn.setAttribute("aria-label", t("currency_pick", "اختر العملة") + " (" + code + ")");
    btn.setAttribute("aria-haspopup", "true");
    btn.title = code;

    var NS = "http://www.w3.org/2000/svg";
    var svg = doc.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");

    var circle = doc.createElementNS(NS, "circle");
    circle.setAttribute("cx", "12");
    circle.setAttribute("cy", "12");
    circle.setAttribute("r", "9");

    var curve = doc.createElementNS(NS, "path");
    curve.setAttribute("d", "M14.8 9.3a3 3 0 0 0-2.8-1.6c-1.6 0-2.7.8-2.7 2 0 1.2.9 1.7 2.9 2.1"
      + " 1.9.4 2.9.9 2.9 2.2 0 1.2-1.1 2.1-2.9 2.1a3.1 3.1 0 0 1-3-1.7");

    var bar = doc.createElementNS(NS, "path");
    bar.setAttribute("d", "M12 6.2v11.6");

    svg.appendChild(circle);
    svg.appendChild(curve);
    svg.appendChild(bar);
    btn.appendChild(svg);

    btn.addEventListener("click", toggle);
    theBtn = btn;
    return btn;
  }

  /* الإغلاق بالنقر خارج اللوحة وبمفتاح Escape */
  doc.addEventListener("click", function (e) {
    if (!panel || !panel.classList.contains("open")) return;
    var wrap = doc.querySelector(".sf-cur-wrap");
    if (wrap && !wrap.contains(e.target)) close();
  });

  doc.addEventListener("keydown", function (e) {
    if (e.key === "Escape") close();
  });

  function mount() {
    if (doc.getElementById("sf-cur-btn")) return;

    var actions = doc.getElementById("dt-actions");
    if (!actions) return;

    injectStyles();

    /* غلاف نسبي: اللوحة مطلقة التموضع فتحتاج مرجعاً
       ملاصقاً للزر لا للشريط كله، وإلا انزاحت عن الزر. */
    var wrap = doc.createElement("div");
    wrap.className = "sf-cur-wrap";
    wrap.appendChild(makeButton());
    buildPanel(wrap);

    /* بعد زرّ اللغة مباشرة ليثبُت الترتيب: الزرّان يُحقنان
       في الفجوة نفسها، فلو تُركا لـ«أيّهما سبق» لاختلف
       ترتيبهما بين صفحة وأخرى. */
    var langWrap = actions.querySelector(".sf-lang-wrap");
    var msgs = actions.querySelector('a[href*="messages.html"]');
    if (langWrap) actions.insertBefore(wrap, langWrap.nextSibling);
    else if (msgs) actions.insertBefore(wrap, msgs);
    else actions.appendChild(wrap);
  }

  if (doc.readyState === "loading") {
    doc.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }

  /* top-bar.js يحقن الشريط بعد التحميل في ثلاث صفحات،
     فتُعاد المحاولة حتّى تجد #dt-actions. */
  global.setTimeout(mount, 0);
  global.setTimeout(mount, 300);

  global.SFCurrencyUI = { open: open, close: close, mount: mount };
})(window);
