(function (root) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var t = function (key) { return root.I18N.t(key); };
  var service = root.SFPromotions;
  var statsDialog = $("home-stats-dialog");
  var promoDialog = $("home-promo-dialog");
  var form = $("home-promo-form");
  var publicRows = [], adminRows = [], current = 0, existing = null;
  var previewUrl = "", busy = false, statsBusy = false;

  function status(id, message, failed) {
    $(id).textContent = message || "";
    $(id).classList.toggle("error", !!failed);
  }
  function show(dialog) {
    if (!dialog.open) dialog.showModal();
    document.body.classList.add("home-modal-open");
  }
  function afterClose(dialog) {
    if (dialog.open) return;
    if (!statsDialog.open && !promoDialog.open) document.body.classList.remove("home-modal-open");
    if (dialog === statsDialog) $("home-stats-toggle").setAttribute("aria-expanded", "false");
    if (dialog === promoDialog) resetEditor();
  }
  function closeDialog(dialog) {
    if (busy) return;
    dialog.close();
    afterClose(dialog);
  }
  [statsDialog, promoDialog].forEach(function (dialog) {
    var close = dialog.querySelector("[data-close-dialog]");
    close.setAttribute("aria-label", t("home_panel_close"));
    close.addEventListener("click", function () { closeDialog(dialog); });
    dialog.addEventListener("cancel", function (event) { event.preventDefault(); closeDialog(dialog); });
    dialog.addEventListener("click", function (event) {
      if (event.target !== dialog || busy) return;
      var rect = dialog.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right ||
          event.clientY < rect.top || event.clientY > rect.bottom) closeDialog(dialog);
    });
    dialog.addEventListener("close", function () {
      afterClose(dialog);
    });
  });
  async function loadStats() {
    if (statsBusy) return;
    statsBusy = true;
    $("stats-grid").hidden = true;
    $("home-stats-retry").hidden = true;
    status("home-stats-status", t("home_stats_loading"));
    try {
      if (!root.sb) throw new Error();
      var result = await root.sb.rpc("get_public_stats");
      if (result.error) throw result.error;
      var row = Array.isArray(result.data) ? result.data[0] : result.data;
      if (!row) throw new Error();
      function format(value) {
        var number = Number(value);
        if (!isFinite(number)) throw new Error();
        return number.toLocaleString("en-US", { maximumFractionDigits: 2 });
      }
      $("stat-factories").textContent = format(row.factories_count);
      $("stat-products").textContent = format(row.products_count);
      $("stat-units").textContent = format(row.units_sold);
      $("stat-revenue").innerHTML = root.I18N.money(format(row.revenue));
      $("stats-grid").hidden = false;
      status("home-stats-status", "");
    } catch (_) {
      status("home-stats-status", t("home_stats_failed"), true);
      $("home-stats-retry").hidden = false;
    } finally { statsBusy = false; }
  }
  var statsToggle = $("home-stats-toggle");
  statsToggle.title = t("stats_title");
  statsToggle.setAttribute("aria-label", t("stats_title"));
  statsToggle.addEventListener("click", function () {
    show(statsDialog);
    statsToggle.setAttribute("aria-expanded", "true");
    loadStats();
  });
  $("home-stats-retry").addEventListener("click", loadStats);

  function renderPublic() {
    var admin = service.isAdmin();
    var hasRows = publicRows.length > 0;
    $("home-promotions").hidden = false;
    $("home-promotions").setAttribute("aria-label", t("promo_admin_title"));
    $("home-promo-manage").hidden = !admin || !hasRows;
    $("home-promo-stage").hidden = false;
    var pages = Math.max(1, Math.ceil(publicRows.length / 3));
    $("home-promo-controls").hidden = pages < 2;
    var stage = $("home-promo-stage");
    stage.replaceChildren();
    current = (current + pages) % pages;
    for (var slot = 0; slot < 3; slot++) {
      var row = publicRows[current * 3 + slot];
      stage.appendChild(promotionCard(row, admin));
    }
    $("home-promo-position").textContent = t("promo_position")
      .replace("{current}", String(current + 1)).replace("{total}", String(pages));
  }
  function promotionCard(row, admin) {
    var card = document.createElement("article");
    card.className = "home-promo-card";
    if (!row) {
      if (admin) {
        var add = $("home-promo-empty-template").content.firstElementChild.cloneNode(true);
        add.querySelectorAll("[data-i18n]").forEach(function (el) {
          el.textContent = t(el.getAttribute("data-i18n"));
        });
        add.addEventListener("click", function () { openManager(); });
        card.appendChild(add);
      } else {
        card.classList.add("home-promo-vacant");
        var placeholder = document.createElement("div");
        placeholder.className = "home-promo-placeholder";
        placeholder.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 5-5 4 4 3-3 6 6"/></svg>';
        var label = document.createElement("span");
        label.textContent = t("promo_empty");
        placeholder.appendChild(label);
        card.appendChild(placeholder);
      }
      return card;
    }
    var heading = document.createElement("div");
    heading.className = "home-promo-card-head";
    var title = document.createElement("h3");
    title.textContent = row.title;
    heading.appendChild(title);
    if (admin) {
      var edit = action("promo_edit", function () { openManager(row); });
      edit.classList.add("home-promo-card-edit");
      edit.title = t("promo_edit");
      edit.setAttribute("aria-label", t("promo_edit") + ": " + row.title);
      edit.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 5 4 4M4 20l4-1L20 7a2.8 2.8 0 0 0-4-4L4 15z"/></svg>';
      heading.appendChild(edit);
    }
    card.appendChild(heading);
    var link = "";
    try { link = service.targetUrl(row.target_url); } catch (_) {}
    var frame = document.createElement(link ? "a" : "div");
    frame.className = "home-promo-card-image";
    if (link) { frame.href = link; frame.target = "_blank"; frame.rel = "noopener noreferrer"; }
    var img = document.createElement("img");
    img.alt = row.title;
    img.src = row.image_url;
    img.addEventListener("error", function () {
      frame.textContent = t("promo_image_failed");
      frame.classList.add("home-panel-status");
    });
    frame.appendChild(img);
    card.appendChild(frame);
    return card;
  }
  async function refreshPublic() {
    try {
      publicRows = (await service.listPublic()).filter(function (row) {
        return row.is_active === true && service.imagePath(row.image_url);
      });
    } catch (_) { publicRows = []; }
    renderPublic();
  }
  $("home-promo-prev").setAttribute("aria-label", t("promo_previous"));
  $("home-promo-next").setAttribute("aria-label", t("promo_next"));
  $("home-promo-prev").addEventListener("click", function () { current--; renderPublic(); });
  $("home-promo-next").addEventListener("click", function () { current++; renderPublic(); });

  function setBusy(value) {
    busy = value;
    promoDialog.querySelectorAll("button, input").forEach(function (el) { el.disabled = value; });
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
    $("promo-title").value = row ? row.title : "";
    $("promo-link").value = row ? row.target_url : "";
    $("promo-order").value = row ? row.sort_order : 0;
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
    $("home-promo-retry").hidden = true;
    try {
      adminRows = await service.listAdmin();
      var list = $("home-promo-list");
      list.replaceChildren();
      adminRows.forEach(function (row) {
        var entry = document.createElement("div");
        entry.className = "home-promo-row";
        var title = document.createElement("span");
        title.textContent = row.title;
        var state = document.createElement("small");
        state.textContent = t(row.is_active ? "promo_visible" : "promo_hidden");
        title.appendChild(state);
        entry.appendChild(title);
        entry.appendChild(action("promo_edit", function () {
          if (!service.isAdmin() || busy) return;
          resetEditor(row);
          $("promo-title").focus();
        }));
        entry.appendChild(action("promo_delete", async function () {
          if (!service.isAdmin() || busy || !root.confirm(t("promo_delete_confirm"))) return;
          setBusy(true);
          try {
            await service.remove(row);
            if (existing && existing.id === row.id) resetEditor();
            status("home-promo-status", t("promo_deleted"));
            await Promise.all([refreshAdmin(), refreshPublic()]);
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
  function openManager(row) {
    if (!service.isAdmin()) return;
    resetEditor(row);
    if (!row) {
      var highestOrder = publicRows.reduce(function (max, item) { return Math.max(max, Number(item.sort_order) || 0); }, -1);
      $("promo-order").value = Math.min(9999, highestOrder + 1);
    }
    status("home-promo-status", "");
    show(promoDialog);
    refreshAdmin();
  }
  $("home-promo-manage").addEventListener("click", function () { openManager(); });
  $("home-promo-new").addEventListener("click", function () {
    if (!service.isAdmin() || busy) return;
    resetEditor();
    status("home-promo-status", "");
    $("promo-title").focus();
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
      title: $("promo-title").value, target_url: $("promo-link").value,
      sort_order: $("promo-order").value, is_active: $("promo-active").checked };
    var file = $("promo-file").files[0];
    setBusy(true);
    status("home-promo-status", t("msg_uploading"));
    try {
      await service.save(values, file);
      resetEditor();
      status("home-promo-status", t("promo_saved"));
      await Promise.all([refreshAdmin(), refreshPublic()]);
    } catch (err) { status("home-promo-status", err.message || t("promo_load_failed"), true); }
    finally { setBusy(false); }
  });
  (root.SF_AUTH_READY || Promise.resolve()).then(refreshPublic).catch(function () { renderPublic(); });
})(window);
