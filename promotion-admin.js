(function (root) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var t = function (key) { return root.I18N.t(key); };
  var service = root.SFPromotions, panel = $("admin-promotions"), form = $("home-promo-form");
  var adminRows = [], existing = null, previewUrl = "", busy = false;
  function status(id, message, failed) {
    $(id).textContent = message || ""; $(id).classList.toggle("error", !!failed);
  }
  function setBusy(value) {
    busy = value;
    panel.querySelectorAll("button, input, select").forEach(function (el) { el.disabled = value; });
    form.setAttribute("aria-busy", String(value));
  }
  function releasePreview() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    previewUrl = "";
  }
  function resetEditor(row) {
    releasePreview();
    existing = row || null;
    form.reset();
    $("promo-link").value = row ? row.target_url : "";
    $("promo-discount-category").value = row && row.discount_category || "";
    $("promo-discount-percent").value = row && row.discount_percent != null ? row.discount_percent : "";
    var highestOrder = adminRows.reduce(function (max, item) { return Math.max(max, Number(item.sort_order) || 0); }, -1);
    $("promo-order").value = row ? row.sort_order : Math.min(9999, highestOrder + 1);
    $("promo-active").checked = row ? row.is_active : true;
    $("promo-preview").hidden = !row;
    if (row) $("promo-preview").src = row.image_url;
    else $("promo-preview").removeAttribute("src");
    $("promo-save").textContent = t("promo_save");
  }
  function action(label, callback) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "home-panel-button";
    button.textContent = t(label);
    button.addEventListener("click", callback);
    return button;
  }
  async function refreshAdmin() {
    if (!service.isAdmin()) return;
    $("home-promo-retry").hidden = true;
    try {
      adminRows = await service.listAdmin();
      var list = $("home-promo-list");
      list.replaceChildren();
      adminRows.forEach(function (row, index) {
        var entry = document.createElement("div");
        entry.className = "home-promo-row";
        if (service.imagePath(row.image_url)) {
          var thumbnail = document.createElement("img");
          thumbnail.className = "admin-promo-thumbnail"; thumbnail.src = row.image_url;
          thumbnail.alt = row.title || t("promo_image"); entry.appendChild(thumbnail);
        }
        var title = document.createElement("span");
        title.textContent = row.title || t("promo_image") + " " + (index + 1);
        var state = document.createElement("small");
        state.textContent = t(row.is_active ? "promo_visible" : "promo_hidden");
        title.appendChild(state);
        entry.appendChild(title);
        entry.appendChild(action("promo_edit", function () {
          if (!service.isAdmin() || busy) return;
          resetEditor(row);
          $("promo-file").focus();
        }));
        entry.appendChild(action("promo_delete", async function () {
          if (!service.isAdmin() || busy || !root.confirm(t("promo_delete_confirm"))) return;
          setBusy(true);
          try {
            await service.remove(row);
            if (existing && existing.id === row.id) resetEditor();
            status("home-promo-status", t("promo_deleted"));
            await refreshAdmin();
          } catch (err) { status("home-promo-status", err.message || t("promo_load_failed"), true); }
          finally { setBusy(false); }
        }));
        list.appendChild(entry);
      });
      if (!adminRows.length) list.textContent = t("promo_empty");
    } catch (_) {
      status("home-promo-status", t("promo_admin_unavailable"), true);
      $("home-promo-retry").hidden = false;
    }
  }
  $("home-promo-new").addEventListener("click", function () {
    if (!service.isAdmin() || busy) return;
    resetEditor();
    status("home-promo-status", "");
    $("promo-file").focus();
  });
  $("home-promo-retry").addEventListener("click", function () {
    status("home-promo-status", "");
    refreshAdmin();
  });
  $("promo-file").addEventListener("change", function () {
    releasePreview();
    var file = this.files[0];
    if (!file) { $("promo-preview").hidden = !existing; if (existing) $("promo-preview").src = existing.image_url; return; }
    try {
      service.validateFile(file);
      previewUrl = URL.createObjectURL(file);
      $("promo-preview").src = previewUrl;
      $("promo-preview").hidden = false;
      status("home-promo-status", "");
    } catch (err) { this.value = ""; $("promo-preview").hidden = true; status("home-promo-status", err.message, true); }
  });
  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    if (!service.isAdmin() || busy || !form.reportValidity()) return;
    var values = { id: existing && existing.id, image_url: existing && existing.image_url,
      title: existing ? existing.title : "", target_url: $("promo-link").value,
      discount_category: $("promo-discount-category").value, discount_percent: $("promo-discount-percent").value,
      sort_order: $("promo-order").value, is_active: $("promo-active").checked };
    var file = $("promo-file").files[0];
    setBusy(true);
    status("home-promo-status", t("msg_uploading"));
    try {
      await service.save(values, file);
      await refreshAdmin();
      resetEditor();
      status("home-promo-status", t("promo_saved"));
    } catch (err) { status("home-promo-status", err.message || t("promo_load_failed"), true); }
    finally { setBusy(false); }
  });
  (root.I18N.categories || []).forEach(function (category) {
    var option = document.createElement("option"); option.value = category.en;
    option.textContent = root.I18N.categoryName(category); $("promo-discount-category").appendChild(option);
  });
  root.SFPromotionAdmin = { show: async function () {
    await (root.SF_AUTH_READY || Promise.resolve());
    if (!service.isAdmin()) { panel.hidden = true; return; }
    if (busy) return;
    status("home-promo-status", "");
    await refreshAdmin();
    if (!existing) resetEditor();
  } };
  root.addEventListener("beforeunload", releasePreview);
})(window);
