
(function () {
  var listEl    = document.getElementById("list");
  var modal     = document.getElementById("reject-modal");
  var reasonEl  = document.getElementById("reject-reason");
  var current   = "pending";
  var factories = [];
  var rejectId  = null;

  /* ===== أدوات ===== */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function fmtDate(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.getFullYear() + "/" + (d.getMonth() + 1) + "/" + d.getDate();
  }

  function statusLabel(s) {
    return s === "approved" ? "معتمد" : s === "rejected" ? "مرفوض" : "قيد المراجعة";
  }

  function showState(msg, isError) {
    listEl.innerHTML = '<div class="state' + (isError ? " error" : "") + '">' + msg + "</div>";
  }

  /* ===== جلب المصانع ===== */
  function loadFactories() {
    listEl.innerHTML = '<div class="state"><div class="spinner"></div>جارٍ التحميل…</div>';

    sb.from("factories")
      .select("*")
      .order("created_at", { ascending: false })
      .then(function (res) {
        if (res.error) {
          showState("تعذّر تحميل المصانع.<br>" + esc(res.error.message), true);
          return;
        }
        factories = res.data || [];
        updateCounts();
        render();
      });
  }

  function updateCounts() {
    var n = { pending: 0, approved: 0, rejected: 0 };
    factories.forEach(function (f) { if (n[f.status] !== undefined) n[f.status]++; });
    document.getElementById("c-pending").textContent  = n.pending  || "";
    document.getElementById("c-approved").textContent = n.approved || "";
    document.getElementById("c-rejected").textContent = n.rejected || "";
  }

  /* ===== العرض ===== */
  function render() {
    var rows = factories.filter(function (f) { return f.status === current; });

    if (!rows.length) {
      showState(
        current === "pending"  ? "لا توجد مصانع قيد المراجعة." :
        current === "approved" ? "لا توجد مصانع معتمدة بعد." :
                                 "لا توجد مصانع مرفوضة."
      );
      return;
    }

    listEl.innerHTML = rows.map(cardHtml).join("");
  }

  function cardHtml(f) {
    var name  = f.name || "مصنع بلا اسم";
    var logo  = f.logo
      ? '<img class="fc-logo" src="' + esc(f.logo) + '" alt="">'
      : '<div class="fc-logo">' + esc(name.charAt(0)) + "</div>";

    var addr = [f.address_city, f.address_district, f.address_street]
      .filter(Boolean).join("، ") || "—";

    var actions =
      f.status === "pending"
        ? '<button class="act approve" data-act="approve" data-id="' + f.id + '">اعتماد</button>' +
          '<button class="act reject"  data-act="reject"  data-id="' + f.id + '">رفض</button>'
        : '<button class="act revert" data-act="pending" data-id="' + f.id + '">إعادة للمراجعة</button>' +
          (f.status === "rejected"
            ? '<button class="act approve" data-act="approve" data-id="' + f.id + '">اعتماد</button>'
            : '<button class="act reject" data-act="reject" data-id="' + f.id + '">رفض</button>');

    return '' +
      '<div class="factory-card" id="fc-' + f.id + '">' +
        '<div class="fc-head">' +
          logo +
          '<div class="fc-info">' +
            '<div class="fc-name">' + esc(name) + "</div>" +
            '<div class="fc-meta">سجل تجاري: <b>' + esc(f.commercial_register || "—") + "</b></div>" +
            '<div class="fc-meta">التسجيل: ' + fmtDate(f.created_at) + "</div>" +
            '<span class="badge ' + f.status + '">' + statusLabel(f.status) + "</span>" +
          "</div>" +
        "</div>" +
        '<button class="toggle-details" data-toggle="' + f.id + '">عرض التفاصيل ▾</button>' +
        '<div class="fc-details" id="d-' + f.id + '">' +
          '<div class="row"><span>الوصف</span><span>' + esc(f.about || "—") + "</span></div>" +
          '<div class="row"><span>المنطقة</span><span>' + esc(f.region_id || "—") + "</span></div>" +
          '<div class="row"><span>العنوان</span><span>' + esc(addr) + "</span></div>" +
          '<div class="row"><span>العنوان المختصر</span><span class="cr">' + esc(f.address_short || "—") + "</span></div>" +
          '<div class="row"><span>الرمز البريدي</span><span class="cr">' + esc(f.address_postal || "—") + "</span></div>" +
          (f.rejection_reason
            ? '<div class="row"><span>سبب الرفض</span><span>' + esc(f.rejection_reason) + "</span></div>"
            : "") +
        "</div>" +
        '<div class="fc-actions">' + actions + "</div>" +
      "</div>";
  }

  /* ===== تغيير الحالة ===== */
  function setStatus(id, status, reason) {
    var card = document.getElementById("fc-" + id);
    if (card) {
      card.querySelectorAll(".act").forEach(function (b) { b.disabled = true; });
    }

    var patch = { status: status };
    if (status === "rejected") patch.rejection_reason = reason || "";
    if (status === "approved" || status === "pending") patch.rejection_reason = "";

    sb.from("factories")
      .update(patch)
      .eq("id", id)
      .select()
      .then(function (res) {
        if (res.error || !res.data || !res.data.length) {
          alert("تعذّر تنفيذ العملية.\n" + (res.error ? res.error.message : "لم يُحدَّث أي صف — تأكد أن حسابك مدير."));
          if (card) card.querySelectorAll(".act").forEach(function (b) { b.disabled = false; });
          return;
        }

        // نجحت — حدّث النسخة المحلية دون إعادة تحميل كامل
        var updated = res.data[0];
        for (var i = 0; i < factories.length; i++) {
          if (factories[i].id === updated.id) { factories[i] = updated; break; }
        }
        updateCounts();
        render();
      });
  }

  /* ===== الأحداث ===== */
  document.querySelectorAll(".tab").forEach(function (tab) {
    tab.addEventListener("click", function () {
      document.querySelectorAll(".tab").forEach(function (t) { t.classList.remove("active"); });
      tab.classList.add("active");
      current = tab.getAttribute("data-status");
      render();
    });
  });

  listEl.addEventListener("click", function (e) {
    var toggle = e.target.closest("[data-toggle]");
    if (toggle) {
      var d = document.getElementById("d-" + toggle.getAttribute("data-toggle"));
      var open = d.classList.toggle("open");
      toggle.textContent = open ? "إخفاء التفاصيل ▴" : "عرض التفاصيل ▾";
      return;
    }

    var btn = e.target.closest("[data-act]");
    if (!btn) return;

    var id  = btn.getAttribute("data-id");
    var act = btn.getAttribute("data-act");

    if (act === "reject") {
      rejectId = id;
      reasonEl.value = "";
      modal.classList.add("open");
      document.body.style.overflow = "hidden";
      setTimeout(function () { reasonEl.focus(); }, 300);
      return;
    }

    /* نفس إصلاح web-admin.html: "approve" صيغة فعل،
       والقاعدة لا تقبل إلا approved. */
    setStatus(id, act === "approve" ? "approved" : act);
  });

  /* ===== نافذة الرفض ===== */
  function closeModal() {
    modal.classList.remove("open");
    document.body.style.overflow = "";
    rejectId = null;
  }

  document.getElementById("reject-cancel").addEventListener("click", closeModal);

  document.getElementById("reject-confirm").addEventListener("click", function () {
    if (!rejectId) return;
    var id = rejectId, reason = reasonEl.value.trim();
    closeModal();
    setStatus(id, "rejected", reason);
  });

  modal.addEventListener("click", function (e) {
    if (e.target === modal) closeModal();
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && modal.classList.contains("open")) closeModal();
  });

  /* ===== البدء: تحقّق أن المستخدم مدير ===== */
  SF_AUTH_READY.then(function () {
    /* ترويسة القائمة الجانبية (سطح المكتب) */
    if (SF_PROFILE) {
      var nameEl = document.getElementById("dash-name");
      var typeEl = document.getElementById("dash-type");
      var avaEl  = document.getElementById("dash-avatar");

      if (nameEl && SF_PROFILE.full_name) nameEl.textContent = SF_PROFILE.full_name;
      if (typeEl) {
        typeEl.textContent = SF_PROFILE.account_type === "factory" ? "حساب مصنع" : "حساب فرد";
      }
      if (avaEl && SF_PROFILE.company_image) {
        avaEl.innerHTML = '<img src="' + SF_PROFILE.company_image + '" alt="">';
      }
    }

    if (!SF_PROFILE || !SF_PROFILE.is_admin) {
      showState("هذه الصفحة للمدير فقط.<br>حسابك لا يملك صلاحية الإدارة.", true);
      document.querySelector(".tabs").style.display = "none";
      return;
    }
    loadFactories();
  });
})();
