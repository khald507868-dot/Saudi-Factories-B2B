/* ===== تقييمات المنتجات ومراجعات المشترين =====
   من اشترى فعلاً وحده يقيّم (بطلب المالك)، والقيد في
   الخادم لا هنا: سياسة RLS تستدعي has_purchased_product،
   فلو تحايل أحد على الواجهة رفضته القاعدة.

   وصاحب المصنع لا يملك حذف تعليق ولا تعديله (بطلب المالك
   صريحاً) — والسياسة لا تعطيه ذلك أصلاً. الحذف للمقيّم
   نفسه وللمشرف وحدهما.

   نفس شكل بقيّة الخدمات: IIFE على global مع حارس ready. */
(function (global) {
  "use strict";

  function t(key, fallback) {
    if (global.I18N && typeof I18N.t === "function") {
      var v = I18N.t(key);
      if (v && v !== key) return v;
    }
    return fallback;
  }

  /* الخدمة تحتاج العميل والجلسة. تُقرأ وقت النداء لا وقت
     التحميل: SF_USER يُملأ بعد وعد الحارس. */
  function ready(needUser) {
    if (!global.sb) {
      return { ok: false, error: t("err_no_backend", "تعذّر الاتصال بالخادم.") };
    }
    if (needUser && !global.SF_USER) {
      return { ok: false, error: t("login_required_action", "يرجى تسجيل الدخول أولاً") };
    }
    return { ok: true };
  }

  /* متوسّط التقييم وعدده لمجموعة منتجات في نداء واحد.
     يُرجِع خريطة { <productId>: {avg, count} }. */
  function loadRatings(productIds) {
    var ids = (productIds || [])
      .map(function (v) { return Number(v); })
      .filter(function (v) { return isFinite(v) && v > 0; });

    if (!ids.length) return Promise.resolve({});

    var g = ready(false);
    if (!g.ok) return Promise.resolve({});

    return global.sb
      .rpc("get_product_ratings", { p_product_ids: ids })
      .then(function (res) {
        if (res.error) throw res.error;
        var map = {};
        (res.data || []).forEach(function (row) {
          map[String(row.product_id)] = {
            avg: Number(row.rating_avg) || 0,
            count: Number(row.rating_count) || 0
          };
        });
        return map;
      })
      .catch(function (err) {
        /* غياب التقييمات لا يُسقط الصفحة: تُعرض بلا نجوم. */
        if (global.console) console.warn("ratings:", err && err.message);
        return {};
      });
  }

  /* مراجعات منتج واحد مع أسماء كاتبيها. */
  function loadReviews(productId, limit, offset) {
    var g = ready(false);
    if (!g.ok) return Promise.reject(new Error(g.error));

    return global.sb
      .rpc("get_product_reviews", {
        p_product_id: Number(productId),
        p_limit: Number(limit) || 20,
        p_offset: Number(offset) || 0
      })
      .then(function (res) {
        if (res.error) throw res.error;
        return res.data || [];
      });
  }

  /* هل يحقّ لي التقييم، وهل قيّمت من قبل؟ */
  function myStatus(productId) {
    var g = ready(true);
    if (!g.ok) return Promise.resolve({ canReview: false, hasReview: false });

    return global.sb
      .rpc("can_review_product", { p_product_id: Number(productId) })
      .then(function (res) {
        if (res.error) throw res.error;
        var row = (res.data && res.data[0]) || {};
        return {
          canReview: row.can_review === true,
          hasReview: row.has_review === true
        };
      })
      .catch(function () {
        return { canReview: false, hasReview: false };
      });
  }

  /* إضافة مراجعة أو تحديثها. upsert لأنّ القاعدة تمنع
     مراجعتين لنفس المشتري ونفس المنتج. */
  function submitReview(productId, rating, body) {
    var g = ready(true);
    if (!g.ok) return Promise.reject(new Error(g.error));

    var stars = parseInt(rating, 10);
    if (!(stars >= 1 && stars <= 5)) {
      return Promise.reject(new Error(t("review_pick_stars", "اختر تقييماً من 1 إلى 5.")));
    }

    var text = String(body == null ? "" : body).trim().slice(0, 2000);

    return global.sb
      .from("product_reviews")
      .upsert({
        product_id: Number(productId),
        author_id: global.SF_USER.id,
        rating: stars,
        body: text
      }, { onConflict: "product_id,author_id" })
      .select()
      .then(function (res) {
        if (res.error) throw res.error;
        /* صفر صفوف مع نجاح ظاهري = رفضته السياسة، وهو ما
           يقع لمن لم يشترِ. لا يُقرأ من رمز الحالة. */
        if (!res.data || !res.data.length) {
          throw new Error(t("review_need_purchase",
            "التقييم متاح لمن اشترى هذا المنتج."));
        }
        return res.data[0];
      });
  }

  function deleteReview(reviewId) {
    var g = ready(true);
    if (!g.ok) return Promise.reject(new Error(g.error));

    return global.sb
      .from("product_reviews")
      .delete()
      .eq("id", Number(reviewId))
      .select()
      .then(function (res) {
        if (res.error) throw res.error;
        return (res.data || []).length > 0;
      });
  }

  /* توزيع النجوم: خمسة صفوف دائماً من الخادم،
     ويُرجَع كخريطة { 5: n, 4: n, ... } لتقرأها الواجهة
     بلا بحث في مصفوفة. */
  function loadBreakdown(productId) {
    var g = ready(false);
    if (!g.ok) return Promise.resolve(null);

    return global.sb
      .rpc("get_rating_breakdown", { p_product_id: Number(productId) })
      .then(function (res) {
        if (res.error) throw res.error;
        var map = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
        (res.data || []).forEach(function (row) {
          map[Number(row.rating)] = Number(row.cnt) || 0;
        });
        return map;
      })
      .catch(function (err) {
        if (global.console) console.warn("breakdown:", err && err.message);
        return null;
      });
  }

  /* ملخّص المصنع لبطاقة المورّد: اعتماد، عدد
     منتجات، مدينة. غيابه لا يُسقِط البطاقة. */
  function loadFactorySummary(factoryId) {
    var g = ready(false);
    if (!g.ok) return Promise.resolve(null);

    return global.sb
      .rpc("get_factory_summary", { p_factory_id: Number(factoryId) })
      .then(function (res) {
        if (res.error) throw res.error;
        var row = (res.data && res.data[0]) || null;
        if (!row) return null;
        return {
          approved: row.is_approved === true,
          products: Number(row.product_count) || 0,
          city: String(row.city || "")
        };
      })
      .catch(function (err) {
        if (global.console) console.warn("factory summary:", err && err.message);
        return null;
      });
  }

  global.SFReviews = {
    loadRatings: loadRatings,
    loadBreakdown: loadBreakdown,
    loadFactorySummary: loadFactorySummary,
    loadReviews: loadReviews,
    myStatus: myStatus,
    submitReview: submitReview,
    deleteReview: deleteReview
  };
})(window);
