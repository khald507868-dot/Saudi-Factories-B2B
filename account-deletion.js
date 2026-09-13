(function () {
  "use strict";
  var row = document.getElementById("delete-account-row");
  var dialog = document.getElementById("delete-account-dialog");
  if (!row || !dialog) return;
  var form = document.getElementById("delete-account-form");
  var checkbox = document.getElementById("delete-account-confirm");
  var submit = document.getElementById("delete-account-submit");
  var cancel = document.getElementById("delete-account-cancel");
  var errorBox = document.getElementById("delete-account-error");
  var busy = false;
  function t(key) { return window.I18N.t(key); }
  function setBusy(value) {
    busy = value;
    checkbox.disabled = cancel.disabled = value;
    submit.disabled = value || !checkbox.checked;
    submit.textContent = t(value ? "account_deleting" : "account_delete");
    form.setAttribute("aria-busy", String(value));
  }
  row.addEventListener("click", function () {
    form.reset(); errorBox.hidden = true; setBusy(false); dialog.showModal();
    cancel.focus();
  });
  checkbox.addEventListener("change", function () { setBusy(busy); });
  cancel.addEventListener("click", function () { if (!busy) dialog.close(); });
  dialog.addEventListener("cancel", function (event) { if (busy) event.preventDefault(); });
  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    if (busy || !checkbox.checked) return;
    errorBox.hidden = true; setBusy(true);
    try {
      // The server derives the account from the authenticated JWT, never a supplied ID.
      var result = await window.sb.functions.invoke("delete-account", {body: {confirmation: "DELETE"}});
      if (result.error || !result.data || result.data.deleted !== true) {
        var code = result.data && result.data.error;
        if (result.error && result.error.context) {
          try { code = (await result.error.context.json()).error; } catch (_) {}
        }
        throw new Error(code === "account_has_orders" ? "account_delete_orders" : "account_delete_failed");
      }
      // Deletion has already succeeded. Cleanup failures must not report a failed deletion.
      try { await window.sb.auth.signOut({scope: "local"}); } catch (_) {}
      window.SF_USER = window.SF_PROFILE = null;
      try {
        ["sf_account", "sf_account_type", "sf_signed_in"].forEach(function (key) { localStorage.removeItem(key); });
        sessionStorage.removeItem("sf_verification_email");
        sessionStorage.removeItem("sf_verification_next");
      } catch (_) {}
      window.location.replace("index.html");
    } catch (error) {
      errorBox.textContent = t(error.message === "account_delete_orders" ? error.message : "account_delete_failed");
      errorBox.hidden = false; setBusy(false);
    }
  });
})();
