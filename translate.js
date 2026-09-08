/* ===== ترجمة نصوص المصانع تلقائيّاً =====
   اسم المنتج ووصفه يكتبهما صاحب المصنع بلغة واحدة، وهذا
   الملفّ يترجمهما إلى لغة الزائر.

   لماذا مترجِم المتصفّح لا واجهة قوقل: واجهة قوقل تحتاج
   مفتاحاً، والمشروع بلا خادم يخفيه فيه — فيصير المفتاح في
   ملفّ .js يقرأه كلّ زائر ويستعمله على حساب المالك.
   ومترجِم المتصفّح (Translator API) يعمل داخل الجهاز بلا
   مفتاح ولا تكلفة ولا إرسال للنصّ إلى أحد.

   وهو في كروم 138+ وإيدج 148+ على سطح المكتب وحده، وليس
   في فايرفوكس ولا سفاري ولا الجوّال — فمن لا يملكه يرى
   النصّ الأصليّ كما هو. وهذا تحسينٌ تدريجيّ: لا شيء ينكسر
   عند غيابه.

   والترجمة تُحفظ في الجلسة فلا تُعاد لكلّ رسم. */
(function (global) {
  "use strict";

  var CACHE_KEY = "sf_tr_cache";
  var mem = {};
  var loaded = false;

  /* الحزم تُنزّل مرّة لكلّ زوج لغات، فتُخزّن الوعود حتّى
     لا يُطلب الزوج نفسه مرّتين في آن. */
  var pending = {};

  function supported() {
    return typeof global.Translator !== "undefined";
  }

  function loadCache() {
    if (loaded) return;
    loaded = true;
    try {
      var raw = global.sessionStorage && sessionStorage.getItem(CACHE_KEY);
      if (raw) mem = JSON.parse(raw) || {};
    } catch (e) { mem = {}; }
  }

  function saveCache() {
    try {
      if (global.sessionStorage) {
        sessionStorage.setItem(CACHE_KEY, JSON.stringify(mem));
      }
    } catch (e) { /* الحصّة ممتلئة أو وضع خاصّ — تعمل بلا حفظ */ }
  }

  /* لغة النصّ: لا نطلب من المصنع تحديدها، فتُستنتج من
     وجود حروف عربية. وهي كافية هنا: المحتوى عربيّ أو
     إنجليزيّ في الغالب الأعمّ. */
  function guessLang(text) {
    return /[؀-ۿ]/.test(String(text || "")) ? "ar" : "en";
  }

  function key(text, from, to) {
    return from + ">" + to + ":" + text;
  }

  /* يُرجِع نصّاً مترجماً، أو الأصل إن تعذّرت الترجمة.
     لا يرمي أبداً: فشل الترجمة لا يجوز أن يُسقط الصفحة. */
  function translate(text, targetLang) {
    var src = String(text == null ? "" : text).trim();
    var to = String(targetLang || "").slice(0, 2).toLowerCase();

    if (!src || !to) return Promise.resolve(src);
    if (!supported()) return Promise.resolve(src);

    var from = guessLang(src);
    if (from === to) return Promise.resolve(src);

    loadCache();
    var k = key(src, from, to);
    if (Object.prototype.hasOwnProperty.call(mem, k)) {
      return Promise.resolve(mem[k]);
    }

    var pairKey = from + ">" + to;
    if (!pending[pairKey]) {
      pending[pairKey] = global.Translator
        .availability({ sourceLanguage: from, targetLanguage: to })
        .then(function (state) {
          if (state === "unavailable") return null;
          return global.Translator.create({
            sourceLanguage: from,
            targetLanguage: to
          });
        })
        .catch(function () { return null; });
    }

    return pending[pairKey].then(function (tr) {
      if (!tr) return src;
      return tr.translate(src).then(function (out) {
        var value = String(out || "").trim() || src;
        mem[k] = value;
        saveCache();
        return value;
      });
    }).catch(function () { return src; });
  }

  /* يترجم عنصراً في مكانه. يبقى النصّ الأصليّ في سمة
     data-sf-src فتُعاد الترجمة عند تغيير اللغة دون أن
     تُترجم ترجمةً سابقة مرّةً أخرى. */
  function translateEl(el, targetLang) {
    if (!el) return;
    var src = el.getAttribute("data-sf-src");
    if (src == null) {
      src = el.textContent || "";
      el.setAttribute("data-sf-src", src);
    }
    if (!String(src).trim()) return;

    translate(src, targetLang).then(function (out) {
      if (out && out !== el.textContent) el.textContent = out;
    });
  }

  /* يترجم كلّ عنصر يحمل data-sf-translate داخل جذر. */
  function translateAll(root, targetLang) {
    var scope = root || global.document;
    if (!scope || !scope.querySelectorAll) return;
    var lang = targetLang
      || (global.I18N && I18N.getLang && I18N.getLang())
      || "ar";
    var nodes = scope.querySelectorAll("[data-sf-translate]");
    for (var i = 0; i < nodes.length; i++) translateEl(nodes[i], lang);
  }

  global.SFTranslate = {
    supported: supported,
    translate: translate,
    translateEl: translateEl,
    translateAll: translateAll,
    guessLang: guessLang
  };
})(window);
