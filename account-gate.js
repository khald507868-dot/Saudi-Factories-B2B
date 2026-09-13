(function () {
  "use strict";
  I18N.applyTranslations();
  var $ = function (id) { return document.getElementById(id); };
  var status = $("gate-status"), busy = false, until = 0;
  function message(key, failed) { status.textContent = I18N.t(key); status.classList.toggle("error", !!failed); }
  function stored(key, fallback) { try { return sessionStorage.getItem(key) || fallback; } catch (_) { return fallback; } }
  function setBusy(value) { busy = value; document.querySelectorAll("button,input").forEach(function (el) { el.disabled = value; }); }
  function destination() {
    var next = stored("sf_verification_next", "index.html");
    return /^(?:index|web-[a-z0-9-]+)\.html(?:[?#].*)?$/.test(next) && !/[\\\r\n]/.test(next) && !/^web-(verify-email|account-pending)\.html/.test(next) ? next : "index.html";
  }
  if (document.body.dataset.accountGate === "verify") {
    $("verification-email").value = stored("sf_verification_email", "");
    $("verification-form").addEventListener("submit", async function (event) {
      event.preventDefault();
      if (busy || !this.reportValidity()) return;
      setBusy(true); message("auth_checking");
      try {
        var result = await sb.auth.verifyOtp({ email: $("verification-email").value.trim(), token: $("verification-code").value.trim(), type: "email" });
        if (result.error || !result.data || !result.data.session || !result.data.user.email_confirmed_at) throw new Error("Invalid verification");
        await SFAccountAccess.finish(destination());
        try { sessionStorage.removeItem("sf_verification_email"); sessionStorage.removeItem("sf_verification_next"); } catch (_) {}
      } catch (_) { message("auth_code_failed", true); }
      finally { setBusy(false); }
    });
    $("resend-code").addEventListener("click", async function () {
      if (busy || Date.now() < until || !$("verification-email").reportValidity()) return;
      setBusy(true);
      try {
        var result = await sb.auth.resend({ type: "signup", email: $("verification-email").value.trim() });
        if (result.error) throw result.error;
        until = Date.now() + 60000; message("auth_code_sent");
      } catch (_) { message("auth_resend_failed", true); }
      finally { setBusy(false); updateResend(); }
    });
    function updateResend() {
      var seconds = Math.max(0, Math.ceil((until - Date.now()) / 1000));
      $("resend-code").disabled = busy || seconds > 0;
      $("resend-code").textContent = I18N.t("auth_resend") + (seconds ? " (" + seconds + ")" : "");
    }
    setInterval(updateResend, 1000);
  } else {
    async function checkApproval() {
      if (busy) return;
      setBusy(true); message("auth_checking");
      try {
        var session = await sb.auth.getSession();
        if (session.error) throw session.error;
        if (!session.data.session) { location.replace("web-login.html"); return; }
        var access = await SFAccountAccess.check();
        if (access.state === "ready") { location.replace("index.html"); return; }
        if (access.state === "email_required") { SFAccountAccess.verifyEmail(access.user.email); return; }
        var rejected = access.state === "rejected";
        $("pending-title").textContent = I18N.t(rejected ? "auth_rejected_title" : "auth_pending_title");
        $("pending-hint").textContent = I18N.t(rejected ? "auth_rejected_hint" : "auth_pending_hint");
        $("rejection-reason").hidden = !rejected || !access.factory.rejection_reason;
        $("rejection-reason").textContent = rejected ? access.factory.rejection_reason || "" : "";
        message("auth_checked");
      } catch (_) { message("auth_check_failed", true); }
      finally { setBusy(false); }
    }
    $("check-approval").addEventListener("click", checkApproval);
    $("gate-signout").textContent = I18N.t("auth_signout");
    $("gate-signout").addEventListener("click", async function () {
      if (busy) return;
      setBusy(true);
      try { var result = await sb.auth.signOut(); if (result.error) throw result.error; location.replace("web-login.html"); }
      catch (_) { message("auth_check_failed", true); setBusy(false); }
    });
    checkApproval();
    setInterval(function () { if (!document.hidden) checkApproval(); }, 30000);
  }
})();
