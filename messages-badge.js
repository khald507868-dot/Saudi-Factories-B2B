/* Shows the total of unread incoming messages on every messages link. */
(function (root) {
  "use strict";

  var channel = null;
  var refreshTimer = null;
  var started = false;

  function ensureStyles() {
    if (document.getElementById("sf-message-badge-style")) return;
    var style = document.createElement("style");
    style.id = "sf-message-badge-style";
    style.textContent =
      ".sf-message-badge-host{position:relative!important}" +
      ".sf-message-total{position:absolute;z-index:30;top:-7px;inset-inline-start:-7px;min-width:20px;height:20px;padding:0 5px;display:inline-flex;align-items:center;justify-content:center;border:2px solid #fff;border-radius:999px;background:#1f6b42;color:#fff;font:800 10px/1 Segoe UI,Tahoma,Arial,sans-serif;box-shadow:0 3px 9px rgba(4,54,27,.25)}" +
      ".bottom-nav .sf-message-total{top:-4px;inset-inline-start:calc(50% - 15px)}";
    document.head.appendChild(style);
  }

  function links() {
    return Array.prototype.slice.call(document.querySelectorAll('a[href*="messages.html"]'));
  }

  function displayCount(count) {
    return count > 99 ? "99+" : String(count);
  }

  function render(count) {
    links().forEach(function (link) {
      link.classList.add("sf-message-badge-host");
      var badge = link.querySelector(".sf-message-total");
      if (!count) {
        if (badge) badge.remove();
        link.removeAttribute("data-unread-total");
        return;
      }

      if (!badge) {
        badge = document.createElement("span");
        badge.className = "sf-message-total";
        badge.setAttribute("aria-hidden", "true");
        link.appendChild(badge);
      }
      badge.textContent = displayCount(count);
      link.setAttribute("data-unread-total", String(count));
      link.setAttribute("aria-label", "الرسائل: " + displayCount(count) + " غير مقروءة");
    });
  }

  function refresh() {
    if (!root.sb || !root.SF_USER) {
      render(0);
      return Promise.resolve(0);
    }

    return root.sb.rpc("get_unread_message_total").then(function (res) {
      if (res.error) throw res.error;
      var count = Math.max(0, Number(res.data || 0));
      render(count);
      return count;
    }).catch(function () {
      /* لا نعرض رقمًا قديمًا أو غير صحيح عند انقطاع الاتصال. */
      render(0);
      return 0;
    });
  }

  function scheduleRefresh() {
    root.clearTimeout(refreshTimer);
    refreshTimer = root.setTimeout(refresh, 80);
  }

  function start() {
    if (started) return;
    started = true;
    ensureStyles();
    if (!root.sb || !root.SF_USER) {
      render(0);
      return;
    }

    refresh();
    channel = root.sb.channel("sf-message-badge-" + root.SF_USER.id)
      .on("postgres_changes", { event: "*", schema: "public", table: "messages" }, scheduleRefresh)
      .subscribe();

    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) refresh();
    });
  }

  if (root.SF_AUTH_READY && typeof root.SF_AUTH_READY.then === "function") {
    root.SF_AUTH_READY.then(start);
  } else {
    root.setTimeout(start, 0);
  }

  root.addEventListener("beforeunload", function () {
    root.clearTimeout(refreshTimer);
    if (channel && root.sb) root.sb.removeChannel(channel);
  });
}(window));
