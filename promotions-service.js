/* Uses the existing home_promotions table and promotion-media bucket.
   Their RLS policies enforce administrator-only writes, including uploads. */
(function (root) {
  "use strict";
  var columns = "id,title,image_url,target_url,is_active,sort_order";
  var bucket = "promotion-media";
  function error(key) { return new Error(root.I18N.t(key)); }
  function isAdmin() {
    return !!(root.SF_USER && root.SF_PROFILE && root.SF_PROFILE.is_admin === true);
  }
  async function ready(admin) {
    await (root.SF_AUTH_READY || Promise.resolve());
    if (admin && !isAdmin()) throw error("promo_admin_only");
    if (!root.sb) throw error("promo_load_failed");
  }
  function targetUrl(value) {
    var text = String(value || "").trim();
    if (!text) return "";
    try {
      var url = new URL(text);
      if (text.length <= 2048 && !/\s/.test(text) && url.protocol === "https:" &&
          url.hostname && !url.username && !url.password) return text;
    } catch (_) {}
    throw error("promo_target_invalid");
  }
  function imagePath(value) {
    try {
      var url = new URL(value);
      var project = new URL(root.SUPABASE_URL);
      var prefix = "/storage/v1/object/public/" + bucket + "/";
      if (url.origin !== project.origin || url.username || url.password || url.search ||
          url.hash || !url.pathname.startsWith(prefix)) return null;
      var path = url.pathname.slice(prefix.length);
      return /^[0-9a-fA-F-]{36}\/[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp|gif)$/.test(path)
        ? path : null;
    } catch (_) { return null; }
  }
  function validateFile(file) {
    if (!file || !["image/jpeg", "image/png", "image/webp", "image/gif"].includes(file.type) ||
        file.size <= 0 || file.size > 5 * 1024 * 1024) throw error("promo_image_invalid");
  }
  async function list(admin) {
    await ready(admin);
    var query = root.sb.from("home_promotions").select(columns);
    if (!admin) query = query.eq("is_active", true);
    var result = await query.order("sort_order").order("created_at").order("id");
    if (result.error) throw result.error;
    return result.data || [];
  }
  async function cleanup(imageUrl) {
    await ready(true);
    var path = imagePath(imageUrl);
    if (!path || !path.startsWith(root.SF_USER.id + "/")) return;
    var used = await root.sb.from("home_promotions").select("id").eq("image_url", imageUrl).limit(1);
    if (used.error || (used.data || []).length) return;
    await root.sb.storage.from(bucket).remove([path]);
  }
  async function save(values, file) {
    await ready(true);
    var title = String(values.title || "").trim();
    if (!title || Array.from(title).length > 120) throw error("promo_title_required");
    var order = Number(values.sort_order);
    if (!Number.isInteger(order) || order < 0 || order > 9999) throw error("promo_order_invalid");
    var link = targetUrl(values.target_url);
    var imageUrl = values.image_url || "";
    if (file) validateFile(file);
    else if (!imagePath(imageUrl)) throw error("promo_image_required");
    var uploaded;
    try {
      if (file) {
        uploaded = await root.SFUpload.uploadFile(file, bucket, "promotions", "image");
        imageUrl = uploaded.url;
      }
      var payload = { title: title, image_url: imageUrl, target_url: link,
        is_active: values.is_active === true, sort_order: order };
      var query = root.sb.from("home_promotions");
      query = values.id ? query.update(payload).eq("id", values.id) : query.insert(payload);
      var result = await query.select(columns).single();
      if (result.error) throw result.error;
      if (!result.data) throw error("promo_admin_only");
      if (uploaded && values.image_url && values.image_url !== imageUrl) {
        await cleanup(values.image_url).catch(function () {});
      }
      return result.data;
    } catch (err) {
      // A timed-out write may have succeeded; cleanup checks references first.
      if (uploaded) await cleanup(uploaded.url).catch(function () {});
      throw err;
    }
  }
  async function remove(promotion) {
    await ready(true);
    var result = await root.sb.from("home_promotions").delete().eq("id", promotion.id).select("id").single();
    if (result.error) throw result.error;
    if (!result.data) throw error("promo_admin_only");
    await cleanup(promotion.image_url).catch(function () {});
  }
  root.SFPromotions = { isAdmin: isAdmin, listPublic: function () { return list(false); },
    listAdmin: function () { return list(true); }, save: save, remove: remove,
    imagePath: imagePath, targetUrl: targetUrl, validateFile: validateFile };
})(window);
