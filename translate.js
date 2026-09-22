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
  function translate(text, targetLang, options) {
    options = options || {};
    function report(state, progress) {
      if (options.onStatus) options.onStatus(state, progress);
    }
    function failure(state) {
      var error = new Error(state);
      error.translationStatus = state;
      return error;
    }
    var src = String(text == null ? "" : text).trim();
    var to = String(targetLang || "").slice(0, 2).toLowerCase();

    if (!src || !to) { report("original"); return Promise.resolve(src); }

    var from = guessLang(src);
    if (from === to) { report("original"); return Promise.resolve(src); }

    loadCache();
    var k = key(src, from, to);
    if (Object.prototype.hasOwnProperty.call(mem, k) && typeof mem[k] === "string" && mem[k] !== src) {
      report("translated");
      return Promise.resolve(mem[k]);
    }
    if (!supported()) { report("unsupported"); return Promise.resolve(src); }
    report("translating");

    var pairKey = from + ">" + to;
    function createTranslator() {
      return global.Translator.create({
        sourceLanguage: from,
        targetLanguage: to,
        monitor: function (monitor) {
          monitor.addEventListener("downloadprogress", function (event) {
            report("downloading", Math.round(Number(event.loaded || 0) * 100));
          });
        }
      });
    }
    if (!pending[pairKey]) {
      try {
        /* Start create() in the click handler itself: don't lose user activation
           while waiting for availability or a language-pack download. */
        var creation = options.userInitiated ? createTranslator() : Promise.resolve(
          global.Translator.availability({ sourceLanguage: from, targetLanguage: to })
        ).then(function (state) {
          if (state === "unavailable") throw failure("unavailable");
          var activation = global.navigator && global.navigator.userActivation;
          if ((state === "downloadable" || state === "downloading") && activation && !activation.isActive) {
            throw failure("activation-required");
          }
          return createTranslator();
        });
        pending[pairKey] = Promise.resolve(creation).catch(function (error) {
          /* Failed attempts are retryable; only successful sessions are reused. */
          delete pending[pairKey];
          throw error;
        });
      } catch (error) {
        pending[pairKey] = Promise.reject(error).catch(function (err) {
          delete pending[pairKey];
          throw err;
        });
      }
    }

    return pending[pairKey].then(function (tr) {
      report("translating");
      return tr.translate(src).then(function (out) {
        var value = String(out || "").trim();
        if (!value || value === src) throw failure("failed");
        mem[k] = value;
        saveCache();
        report("translated");
        return value;
      });
    }).catch(function (error) {
      var state = error && error.translationStatus;
      if (!state) {
        state = error && error.name === "NotAllowedError" ? "activation-required"
          : error && error.name === "NotSupportedError" ? "unavailable" : "failed";
      }
      report(state);
      return src;
    });
  }

  /* يترجم عنصراً في مكانه. يبقى النصّ الأصليّ في سمة
     data-sf-src فتُعاد الترجمة عند تغيير اللغة دون أن
     تُترجم ترجمةً سابقة مرّةً أخرى. */
  function translateEl(el, targetLang, options) {
    if (!el) return;
    var request = (el.sfTranslationRequest || 0) + 1;
    el.sfTranslationRequest = request;
    var src = el.getAttribute("data-sf-src");
    if (src == null) {
      src = el.textContent || "";
      el.setAttribute("data-sf-src", src);
    }
    options = options || {};
    function current() {
      return el.sfTranslationRequest === request && el.getAttribute("data-sf-src") === src;
    }

    return translate(src, targetLang, {
      userInitiated: options.userInitiated,
      onStatus: function (state, progress) {
        if (current() && options.onStatus) options.onStatus(state, progress);
      }
    }).then(function (out) {
      /* Live data or a later language choice supersedes an older request. */
      if (!current()) return;
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
