/* ============================================================
   الموقع الجغرافي — geo-location.js
   أُضيف 2026-09-03 بطلب المالك: أيقونة موقع في الشريط العلوي،
   يلصق فيها المستخدم رابط موقعه من قوقل ماب.

   الفرق بين الحسابين مقصود ومحفوظ في القاعدة لا هنا:
     • المصنع → نقطة خضراء في موقعه يراها الجميع (factories).
     • الفرد   → لا يظهر على الخريطة؛ موقعه لتوصيل الطلبية
                 وحدها (profiles، تحرسها RLS).

   الترتيب: i18n → CDN → supabase-config → auth-guard → هذا الملف.
   ============================================================ */
(function (global) {
  "use strict";

  /* ===== استخراج الإحداثيات من رابط قوقل ماب =====

     الأشكال المدعومة:
       .../maps/@24.7136,46.6753,15z
       .../maps/place/X/@24.7136,46.6753,17z/data=...
       .../maps?q=24.7136,46.6753
       .../maps?ll=24.7136,46.6753
       أي نصّ فيه "24.7136, 46.6753"

     غير المدعوم: الروابط المختصرة (maps.app.goo.gl و goo.gl/maps).
     هذه لا تحمل الإحداثيات في نصّها — هي محفوظة عند قوقل ولا
     تُعرف إلا بفتح الرابط، والمتصفح يمنع ذلك (CORS) ولا خادم
     هنا يفعلها. فنكشفها ونطلب من المستخدم الرابط الطويل بدل
     رفضٍ صامت يحيّره. */

  var SHORT_HOSTS = /(maps\.app\.goo\.gl|goo\.gl\/maps)/i;

  /* @lat,lng أو q=/ll= أو زوج صريح. الترتيب مهم: @ أدقّ من
     المسح العام لأنه موضع الكاميرا الفعلي. */
  var PATTERNS = [
    /@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)/,
    /[?&](?:q|ll|daddr|sll)=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)/i,
    /!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)/,
    /(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})/
  ];

  function isShortLink(text) {
    return SHORT_HOSTS.test(String(text || ""));
  }

  /* يرجع {lat, lng} أو null. لا يرمي استثناءً: المُدخل نصّ
     يكتبه المستخدم، والفشل حالة عادية لا خطأ برمجي. */
  function parseMapUrl(text) {
    var s = String(text || "").trim();
    if (!s) return null;

    for (var i = 0; i < PATTERNS.length; i++) {
      var m = s.match(PATTERNS[i]);
      if (!m) continue;

      var lat = parseFloat(m[1]);
      var lng = parseFloat(m[2]);
      if (!isFinite(lat) || !isFinite(lng)) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;

      /* 0,0 نقطة في المحيط الأطلسي — قراءة خاطئة دائماً. */
      if (lat === 0 && lng === 0) continue;

      return { lat: lat, lng: lng };
    }
    return null;
  }

  /* حدود المملكة تقريباً. خارجها ليس خطأ يمنع الحفظ — قد يكون
     مصنعاً خارج السعودية — لكنه يستحق تنبيهاً. */
  function insideSaudi(lat, lng) {
    return lat >= 15.5 && lat <= 32.5 && lng >= 34 && lng <= 56;
  }

  /* ===== الحفظ =====
     الوجهة تتبع نوع الحساب، لا اختيار الواجهة: حساب المصنع
     يكتب في صفّ مصنعه، والفرد في ملفه الشخصي. */
  function ready() {
    if (!global.sb || !global.SF_USER) {
      return Promise.reject(new Error("يجب تسجيل الدخول أولاً"));
    }
    return Promise.resolve();
  }

  function isFactoryAccount() {
    return !!(global.SF_PROFILE && global.SF_PROFILE.account_type === "factory");
  }

  function save(mapUrl) {
    return ready().then(function () {
      var point = parseMapUrl(mapUrl);
      if (!point) {
        throw new Error(isShortLink(mapUrl)
          ? global.I18N ? I18N.t("geo_short_link") : "الرابط مختصر — افتحه في المتصفح وانسخ الرابط الطويل."
          : global.I18N ? I18N.t("geo_bad_link") : "لم نتعرّف على الرابط.");
      }

      var payload = {
        lat: point.lat,
        lng: point.lng,
        map_url: String(mapUrl).slice(0, 2048)
      };

      if (!isFactoryAccount()) {
        /* الفرد: يُحدَّث ملفه الشخصي، وRLS تحصره في صفّه. */
        return global.sb.from("profiles")
          .update(payload)
          .eq("id", global.SF_USER.id)
          .select("lat, lng")
          .then(function (res) {
            if (res.error) throw res.error;
            return point;
          });
      }

      /* المصنع: يُحدَّث صفّ المصنع الذي يملكه. */
      return global.sb.from("factories")
        .update(payload)
        .eq("owner_id", global.SF_USER.id)
        .select("id, lat, lng")
        .then(function (res) {
          if (res.error) throw res.error;
          if (!res.data || !res.data.length) {
            throw new Error(global.I18N ? I18N.t("geo_no_factory")
                                        : "لا يوجد مصنع مرتبط بحسابك.");
          }
          return point;
        });
    });
  }

  /* الموقع المحفوظ للمستخدم الحالي، أو null. */
  function loadMine() {
    return ready().then(function () {
      var table = isFactoryAccount() ? "factories" : "profiles";
      var column = isFactoryAccount() ? "owner_id" : "id";
      return global.sb.from(table)
        .select("lat, lng, map_url")
        .eq(column, global.SF_USER.id)
        .maybeSingle()
        .then(function (res) {
          if (res.error || !res.data) return null;
          return res.data;
        });
    });
  }

  /* ===== نقاط الخريطة =====
     المصانع وحدها. لا استعلام عن profiles هنا إطلاقاً —
     وهو ما يجعل عدم ظهور الأفراد بنيةً لا شرطاً. */
  function loadFactoryPins() {
    if (!global.sb) return Promise.resolve([]);
    return global.sb.from("factories")
      .select("id, name, lat, lng")
      .not("lat", "is", null)
      .not("lng", "is", null)
      .limit(500)
      .then(function (res) {
        if (res.error || !res.data) return [];
        return res.data.filter(function (row) {
          return isFinite(Number(row.lat)) && isFinite(Number(row.lng));
        });
      })
      .catch(function () { return []; });
  }

  global.SFGeo = {
    parseMapUrl: parseMapUrl,
    isShortLink: isShortLink,
    insideSaudi: insideSaudi,
    isFactoryAccount: isFactoryAccount,
    save: save,
    loadMine: loadMine,
    loadFactoryPins: loadFactoryPins
  };
})(window);
