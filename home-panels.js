(function (root) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var t = function (key) { return root.I18N.t(key); };
  var service = root.SFPromotions;
  var statsDialog = $("home-stats-dialog");
  var publicRows = [], statsBusy = false;

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
    document.body.classList.remove("home-modal-open");
    if (dialog === statsDialog) $("home-stats-toggle").setAttribute("aria-expanded", "false");
  }
  function closeDialog(dialog) {
    dialog.close();
    afterClose(dialog);
  }
  [statsDialog].forEach(function (dialog) {
    var close = dialog.querySelector("[data-close-dialog]");
    close.setAttribute("aria-label", t("home_panel_close"));
    close.addEventListener("click", function () { closeDialog(dialog); });
    dialog.addEventListener("cancel", function (event) { event.preventDefault(); closeDialog(dialog); });
    dialog.addEventListener("click", function (event) {
      if (event.target !== dialog) return;
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
    $("home-promotions").hidden = false;
    $("home-promotions").setAttribute("aria-label", t("promo_admin_title"));
    $("home-promo-stage").hidden = false;
    var stage = $("home-promo-stage");
    if (stage.sfStopScroll) stage.sfStopScroll();
    stage.replaceChildren();
    stage.classList.toggle("is-single", publicRows.length <= 1);
    if (!publicRows.length) stage.appendChild(promotionCard(null));
    publicRows.forEach(function (row) { stage.appendChild(promotionCard(row)); });
    if (publicRows.length > 1) {
      root.SFBestsellersScroll.mount(stage, {
        itemSelector: ".home-promo-card", sectionSelector: ".home-promotions",
        copyClass: "home-promo-copy", repeatToFill: true, pauseOnHover: false
      });
    }
  }
  function promotionCard(row) {
    var card = document.createElement("article");
    card.className = "home-promo-card";
    if (!row) {
        card.classList.add("home-promo-vacant");
        var placeholder = document.createElement("div");
        placeholder.className = "home-promo-placeholder";
        placeholder.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 5-5 4 4 3-3 6 6"/></svg>';
        var label = document.createElement("span");
        label.textContent = t("promo_empty");
        placeholder.appendChild(label);
        card.appendChild(placeholder);
      return card;
    }
    var heading = document.createElement("div");
    heading.className = "home-promo-card-head";
    if (row.title) {
      var title = document.createElement("h3");
      title.textContent = row.title;
      heading.appendChild(title);
    }
    if (heading.childElementCount) card.appendChild(heading);
    var link = "";
    try { link = service.targetUrl(row.target_url); } catch (_) {}
    var frame = document.createElement(link ? "a" : "div");
    frame.className = "home-promo-card-image";
    if (link) { frame.href = link; frame.target = "_blank"; frame.rel = "noopener noreferrer"; }
    var img = document.createElement("img");
    img.alt = row.title || t("promo_image");
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
  (root.SF_AUTH_READY || Promise.resolve()).then(refreshPublic).catch(function () { renderPublic(); });
  root.addEventListener("pageshow", function (event) { if (event.persisted) refreshPublic(); });
})(window);
