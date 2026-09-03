/* المفضّلة والطلبات والفواتير — واجهة عميل فوق جداول Supabase.
 *
 * تتبع الشكل نفسه لبقية الخدمات: IIFE فوق global، وحارس ready()
 * يرفض بالعربية ما لم يوجد sb وSF_USER معاً.
 *
 * ملاحظة: تُحمَّل بعد supabase-config.js، وتقرأ SF_USER بكسل
 * وقت الاستدعاء لا وقت التعريف — فقد تسبق auth-guard.js أو تليه.
 */
(function (root) {
  "use strict";

  function ready() {
    if (!root.sb || !root.SF_USER) {
      return Promise.reject(new Error("يجب تسجيل الدخول أولاً"));
    }
    return Promise.resolve();
  }

  /* الحالات التي تُعدّ الطلب منتهياً — وهي المصدر الوحيد لهذا
   * التعريف، فصفحتا الطلبات والفواتير تقرآن منه بدل تكراره. */
  var DONE_STATUSES = ["completed", "paid", "shipped", "processing"];
  var PAID_STATUSES = ["completed", "paid"];

  root.SFFavorites = {
    /* قائمة المفضّلة مع بيانات المنتج ومصنعه.
     * صفّ منتجه محذوف يعود products = null، فتُرشَّح هنا لا في
     * الصفحة — وإلّا رسمت الصفحة بطاقة فارغة. */
    load: function () {
      return ready().then(function () {
        return root.sb.from("favorites")
          .select("id, product_id, created_at, products(id, factory_id, name, price, image, images, factories(name))")
          .eq("user_id", root.SF_USER.id)
          .order("created_at", { ascending: false });
      }).then(function (res) {
        if (res.error) throw res.error;
        return (res.data || []).filter(function (r) { return r.products; });
      });
    },

    /* معرّفات المنتجات المفضّلة فقط — استعلام خفيف تستخدمه
     * الصفحات لتلوين القلوب دون جلب بيانات المنتجات. */
    loadIds: function () {
      return ready().then(function () {
        return root.sb.from("favorites")
          .select("product_id")
          .eq("user_id", root.SF_USER.id);
      }).then(function (res) {
        if (res.error) throw res.error;
        return (res.data || []).map(function (r) { return Number(r.product_id); });
      });
    },

    add: function (productId) {
      return ready().then(function () {
        return root.sb.from("favorites")
          .insert({ user_id: root.SF_USER.id, product_id: Number(productId) })
          .select();
      }).then(function (res) {
        /* 23505 = تكرار المفتاح الفريد: المنتج مفضّل أصلاً.
         * ليس خطأً من منظور المستخدم — النتيجة المطلوبة قائمة. */
        if (res.error && res.error.code !== "23505") throw res.error;
        return true;
      });
    },

    remove: function (productId) {
      return ready().then(function () {
        return root.sb.from("favorites")
          .delete()
          .eq("user_id", root.SF_USER.id)
          .eq("product_id", Number(productId))
          .select();
      }).then(function (res) {
        if (res.error) throw res.error;
        return true;
      });
    },

    /* تبديل الحالة. تعيد true إذا صار مفضّلاً وfalse إذا أُزيل،
     * فتستطيع الصفحة تحديث القلب من القيمة العائدة مباشرة. */
    toggle: function (productId, isFavoriteNow) {
      return isFavoriteNow
        ? this.remove(productId).then(function () { return false; })
        : this.add(productId).then(function () { return true; });
    }
  };

  root.SFOrders = {
    DONE_STATUSES: DONE_STATUSES,
    PAID_STATUSES: PAID_STATUSES,

    /* الطلبات مع أصنافها واسم المصنع.
     * سياسة orders_select_party تتكفّل بالترشيح على الخادم، فلا
     * حاجة لـ eq("buyer_id") — ولو أُضيفت لحجبت طلبات وصلت
     * صاحب المصنع وهو طرف فيها. */
    load: function (statuses) {
      return ready().then(function () {
        var q = root.sb.from("orders")
          .select("id, status, total, subtotal, currency, created_at, factory_id, " +
                  "factories(name), order_items(id, product_name, unit_price, quantity, line_total)")
          .order("created_at", { ascending: false });
        if (statuses && statuses.length) q = q.in("status", statuses);
        return q;
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.data || [];
      });
    },

    /* الطلبات المنتهية — صفحة "طلباتي" */
    loadCompleted: function () { return this.load(DONE_STATUSES); },

    /* الطلبات المدفوعة — صفحة "الفواتير" */
    loadInvoices: function () { return this.load(PAID_STATUSES); }
  };
})(window);
