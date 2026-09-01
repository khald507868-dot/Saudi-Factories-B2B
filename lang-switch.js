/* زر تغيير اللغة المشترك — يُحقن في الشريط العلوي لكل صفحات web.
   كان اختيار اللغة داخل صفحة الإعدادات وحدها، فنُقل إلى الشريط
   ليكون متاحاً من أي صفحة بدل الذهاب للإعدادات.

   ملف واحد لا نسخة في كل صفحة: القائمة ثلاثون لغة، وتكرارها
   في أربع عشرة صفحة يجعل إضافة لغة تعديلاً في أربع عشرة موضعاً.

   القائمة يجب ألا تذكر رمزاً لا يوجد في dict داخل i18n.js،
   وإلا ظهرت الإنجليزية وبدا الاختيار معطلاً. */
(function (global) {
  "use strict";

  var LANGUAGES = [
    ["العربية", "Arabic", "ar"],
    ["الإنجليزية", "English", "en"],
    ["الفرنسية", "Français", "fr"],
    ["الإسبانية", "Español", "es"],
    ["الألمانية", "Deutsch", "de"],
    ["الإيطالية", "Italiano", "it"],
    ["البرتغالية", "Português", "pt"],
    ["الهولندية", "Nederlands", "nl"],
    ["السويدية", "Svenska", "sv"],
    ["البولندية", "Polski", "pl"],
    ["اليونانية", "Ελληνικά", "el"],
    ["الروسية", "Русский", "ru"],
    ["التركية", "Türkçe", "tr"],
    ["الفارسية", "فارسی", "fa"],
    ["الأردية", "اردو", "ur"],
    ["الهندية", "हिन्दी", "hi"],
    ["البنغالية", "বাংলা", "bn"],
    ["البنجابية", "ਪੰਜਾਬੀ", "pa"],
    ["التاميلية", "தமிழ்", "ta"],
    ["التايلاندية", "ไทย", "th"],
    ["الفيتنامية", "Tiếng Việt", "vi"],
    ["الإندونيسية", "Bahasa Indonesia", "id"],
    ["الماليزية", "Bahasa Melayu", "ms"],
    ["الصينية (المبسطة)", "中文 (简体)", "zh"],
    ["اليابانية", "日本語", "ja"],
    ["الكورية", "한국어", "ko"],
    ["العبرية", "עברית", "he"],
    ["الكردية", "Kurdî", "ku"],
    ["الأمهرية", "አማርኛ", "am"],
    ["السواحيلية", "Kiswahili", "sw"]
  ];
  function t(key, fallback) {
    if (!global.I18N || !global.I18N.t) return fallback;
    var v = global.I18N.t(key);
    return (v && v !== key) ? v : fallback;
  }

  function currentEntry() {
    var code = global.I18N ? global.I18N.getLang() : "ar";
    var hit = LANGUAGES.filter(function (l) { return l[2] === code; })[0];
    return hit || LANGUAGES[0];
  }

  /* الأنماط داخل الملف لا في كل صفحة، وتُحقن مرة واحدة */
  function injectStyles() {
    if (document.getElementById("sf-lang-styles")) return;
    var css = [
      /* مطابق لـ .dt-icon في desktop.css: مربّع 40×40 بنفس الإطار والظل */
      ".sf-lang-wrap{position:relative;display:inline-flex}",
      ".sf-lang-btn{width:40px;height:40px;border:1px solid #c7dfce;background:#ffffff;",
      "border-radius:10px;display:flex;align-items:center;justify-content:center;",
      "cursor:pointer;position:relative;padding:0;font:inherit;",
      "box-shadow:0 2px 6px rgba(4,54,27,0.04);",
      "transition:background .18s ease,border-color .18s ease,box-shadow .18s ease}",
      ".sf-lang-btn:hover,.sf-lang-btn.open{background:#f0f7f2;border-color:#8fbe9e;",
      "box-shadow:0 4px 10px rgba(4,54,27,0.10)}",
      ".sf-lang-btn svg{width:22px;height:22px;stroke:#04361b;fill:none;stroke-width:1.9}",

      /* لوحة منسدلة تحت الزر مباشرة، لا ورقة سفلية */
      ".sf-lang-panel{position:absolute;top:calc(100% + 10px);z-index:200;",
      "background:#fff;border-radius:10px;width:280px;",
      "box-shadow:0 6px 24px rgba(4,54,27,0.18);border:1px solid #e2ebe5;",
      "padding:14px 0 10px;opacity:0;visibility:hidden;transform:translateY(-6px);",
      "transition:opacity .15s ease,transform .15s ease,visibility .15s}",
      ".sf-lang-panel.open{opacity:1;visibility:visible;transform:translateY(0)}",

      /* اللوحة تتبع الزر: من اليمين في العربية ومن اليسار في
         الإنجليزية — مرآة لا ترتيب ثابت، فلها نظير ltr */
      ".sf-lang-panel{right:0}",
      'html[dir="ltr"] .sf-lang-panel{right:auto;left:0}',

      /* سهم صغير يربط اللوحة بالزر */
      ".sf-lang-panel::before{content:'';position:absolute;top:-7px;",
      "width:12px;height:12px;background:#fff;border-inline-start:1px solid #e2ebe5;",
      "border-top:1px solid #e2ebe5;transform:rotate(45deg);right:14px}",
      'html[dir="ltr"] .sf-lang-panel::before{right:auto;left:14px}',

      ".sf-lang-title{font-size:14.5px;font-weight:700;color:#12331d;",
      "padding:0 16px 10px;margin:0}",

      ".sf-lang-list{max-height:320px;overflow-y:auto}",

      /* صف اللغة: زر اختيار دائري ثم الاسم */
      ".sf-lang-item{display:flex;align-items:center;gap:10px;width:100%;border:0;",
      "background:none;font:inherit;font-size:13.5px;text-align:start;",
      "padding:9px 16px;cursor:pointer;color:#12331d}",
      ".sf-lang-item:hover{background:#f2f8f4}",
      ".sf-lang-item + .sf-lang-item{border-top:1px solid #f0f4f1}",

      ".sf-radio{width:16px;height:16px;border-radius:50%;border:1.5px solid #9db3a5;",
      "flex-shrink:0;position:relative;box-sizing:border-box}",
      ".sf-lang-item.selected .sf-radio{border-color:#1f6b42}",
      ".sf-lang-item.selected .sf-radio::after{content:'';position:absolute;",
      "inset:3px;border-radius:50%;background:#1f6b42}",
      ".sf-lang-item.selected{font-weight:700}",

      ".sf-lang-more{display:block;width:100%;border:0;background:none;font:inherit;",
      "font-size:13px;color:#1f6b42;cursor:pointer;padding:10px 16px 2px;",
      "text-align:start;border-top:1px solid #eef2ef;margin-top:6px}",
      ".sf-lang-more:hover{text-decoration:underline}"
    ].join("");
    var st = document.createElement("style");
    st.id = "sf-lang-styles";
    st.textContent = css;
    document.head.appendChild(st);
  }

  var panel = null, listEl = null, moreBtn = null, theBtn = null;
  var expanded = false;

  /* اللغتان الرئيستان أولاً كما في المرجع، والبقية
     خلف "لغات أخرى" لأن القائمة ثلاثون لغة ولا تتسع لوحة منسدلة */
  var PRIMARY = ["ar", "en"];

  function buildPanel(wrap) {
    if (panel) return;
    panel = document.createElement("div");
    panel.className = "sf-lang-panel";

    var title = document.createElement("p");
    title.className = "sf-lang-title";
    title.textContent = t("lang_modal_title", "\u062a\u063a\u064a\u064a\u0631 \u0627\u0644\u0644\u063a\u0629");

    listEl = document.createElement("div");
    listEl.className = "sf-lang-list";

    moreBtn = document.createElement("button");
    moreBtn.type = "button";
    moreBtn.className = "sf-lang-more";
    moreBtn.addEventListener("click", function () {
      expanded = !expanded;
      render();
    });

    panel.appendChild(title);
    panel.appendChild(listEl);
    panel.appendChild(moreBtn);
    wrap.appendChild(panel);
  }

  function render() {
    var current = global.I18N ? global.I18N.getLang() : "ar";
    listEl.innerHTML = "";

    var shown = expanded ? LANGUAGES : LANGUAGES.filter(function (l) {
      /* لغة المستخدم تظهر دائماً حتى لو لم تكن من الرئيستين */
      return PRIMARY.indexOf(l[2]) !== -1 || l[2] === current;
    });

    shown.forEach(function (l) {
      var name = l[0], code = l[2];
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "sf-lang-item" + (code === current ? " selected" : "");

      var radio = document.createElement("span");
      radio.className = "sf-radio";

      var label = document.createElement("span");
      label.textContent = name + " - " + String(code).toUpperCase();

      btn.appendChild(radio);
      btn.appendChild(label);
      btn.addEventListener("click", function () {
        if (code === current) { close(); return; }
        /* تغيير اللغة دائماً بإعادة تحميل كاملة، لا بإعادة رسم حية */
        global.I18N.setLang(code);
        window.location.reload();
      });
      listEl.appendChild(btn);
    });

    moreBtn.textContent = expanded
      ? t("lang_show_less", "\u0639\u0631\u0636 \u0623\u0642\u0644")
      : t("lang_more", "\u0644\u063a\u0627\u062a \u0623\u062e\u0631\u0649");
  }

  function open() {
    render();
    panel.classList.add("open");
    if (theBtn) theBtn.classList.add("open");
  }

  function close() {
    if (!panel) return;
    expanded = false;
    panel.classList.remove("open");
    if (theBtn) theBtn.classList.remove("open");
  }

  function toggle() {
    if (panel && panel.classList.contains("open")) { close(); } else { open(); }
  }

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") close();
  });

  /* الضغط خارج اللوحة يغلقها */
  document.addEventListener("click", function (e) {
    if (!panel || !panel.classList.contains("open")) return;
    if (panel.contains(e.target)) return;
    if (theBtn && theBtn.contains(e.target)) return;
    close();
  });

  /* أيقونة كرة أرضية لا علم دولة: رموز الأعلام لا تُرسم في
     متصفّحات ويندوز فتظهر حرفين (SA)، وهذا ما رآه المالك.
     الأيقونة وسم مثل بقية أيقونات الشريط. */
  function makeButton() {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "sf-lang-btn";
    btn.id = "sf-lang-btn";
    btn.setAttribute("aria-label", t("row_language", "\u0627\u0644\u0644\u063a\u0629"));
    btn.title = currentEntry()[0];

    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");

    var circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("cx", "12");
    circle.setAttribute("cy", "12");
    circle.setAttribute("r", "9");

    var horiz = document.createElementNS("http://www.w3.org/2000/svg", "path");
    horiz.setAttribute("d", "M3 12h18");

    var vert = document.createElementNS("http://www.w3.org/2000/svg", "path");
    vert.setAttribute("d", "M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18");

    svg.appendChild(circle);
    svg.appendChild(horiz);
    svg.appendChild(vert);
    btn.appendChild(svg);

    btn.addEventListener("click", toggle);
    theBtn = btn;
    return btn;
  }

  function mount() {
    if (document.getElementById("sf-lang-btn")) return;

    /* الزر في الصفحة الرئيسة وحدها بطلب المالك، وهي
       الوحيدة التي تحمل شريط الأدوات #dt-actions. */
    var actions = document.getElementById("dt-actions");
    if (!actions) return;

    injectStyles();

    /* غلاف نسبي: اللوحة مطلقة التموضع فتحتاج مرجعاً
       ملاصقاً للزر لا للشريط كله، وإلا انزاحت عن الزر. */
    var wrap = document.createElement("div");
    wrap.className = "sf-lang-wrap";
    wrap.appendChild(makeButton());
    buildPanel(wrap);

    var cart = actions.querySelector('a[href="web-cart.html"]');
    if (cart && cart.parentNode === actions) {
      actions.insertBefore(wrap, cart.nextSibling);
    } else {
      actions.appendChild(wrap);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }

  global.SFLang = { open: open, close: close };
})(window);
