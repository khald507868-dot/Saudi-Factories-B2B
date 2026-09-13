// UI gate. Email confirmation is enforced by Supabase Auth; write access is
// also enforced by the account-approval migration, never by localStorage.
(function (root) {
  "use strict";
  async function check() {
    var result = await root.sb.auth.getUser();
    if (result.error) throw result.error;
    var user = result.data && result.data.user;
    if (!user) return { state: "signed_out" };
    if (!user.email_confirmed_at) return { state: "email_required", user: user };
    var profile = await root.sb.from("profiles").select("account_type,full_name,phone,email,is_admin,company_image,gender,country_flag,country_code,birthdate").eq("id", user.id).single();
    if (profile.error || !profile.data) throw profile.error || new Error("Profile unavailable");
    if (!["individual", "factory"].includes(profile.data.account_type)) throw new Error("Account type unavailable");
    var access = { state: "ready", user: user, profile: profile.data };
    if (profile.data.account_type === "factory" && profile.data.is_admin !== true) {
      var factory = await root.sb.from("factories").select("id,status,rejection_reason").eq("owner_id", user.id).order("id").limit(1).maybeSingle();
      if (factory.error) throw factory.error;
      access.factory = factory.data;
      if (!factory.data || factory.data.status !== "approved") {
        access.state = factory.data && factory.data.status === "rejected" ? "rejected" : "pending";
      }
    }
    return access;
  }
  function verifyEmail(email, next) {
    try {
      sessionStorage.setItem("sf_verification_email", email || "");
      sessionStorage.setItem("sf_verification_next", next || "index.html");
    } catch (_) {}
    root.location.replace("web-verify-email.html");
  }
  function route(access, next) {
    if (access.state === "signed_out") { root.location.replace("web-login.html"); return false; }
    if (access.state === "email_required") { verifyEmail(access.user.email, next); return false; }
    if (access.state === "pending" || access.state === "rejected") {
      root.location.replace("web-account-pending.html"); return false;
    }
    return access.state === "ready";
  }
  async function finish(next) {
    var access = await check();
    if (route(access, next)) root.location.replace(next || "index.html");
    return access;
  }
  async function signUp(values) {
    // Do not silently create an authenticated user if confirmation was disabled.
    var response = await fetch(root.SUPABASE_URL + "/auth/v1/settings", { headers: { apikey: root.SUPABASE_KEY } });
    if (!response.ok) throw new Error(root.I18N.t("auth_check_failed"));
    var settings = await response.json();
    if (settings.mailer_autoconfirm !== false) throw new Error(root.I18N.t("auth_verification_unavailable"));
    var signedOut = await root.sb.auth.signOut({ scope: "local" });
    if (signedOut.error) throw signedOut.error;
    var result = await root.sb.auth.signUp(values);
    if (!result.error && result.data && result.data.session) {
      await root.sb.auth.signOut();
      throw new Error(root.I18N.t("auth_verification_unavailable"));
    }
    return result;
  }
  root.SFAccountAccess = { check: check, route: route, finish: finish, verifyEmail: verifyEmail, signUp: signUp };
})(window);
