/* ===== منتقي العملة وتحويل الأسعار المعروضة =====
   الأسعار محفوظة بالريال دائماً، وهذا الملفّ يحوّل المعروض
   وحده. الطلب والفاتورة يبقيان بالريال — وقاعدة البيانات
   تفرض ذلك بقيد check (currency = 'SAR') على الجدولين،
   وهو قيد مقصود لا نلتفّ عليه من المتصفّح.

   لماذا أسعار ثابتة لا خدمة حيّة: قوقل أغلقت واجهة أسعار
   الصرف سنة 2011، وما يُسمّى «أسعار قوقل» اليوم كشطٌ لصفحة
   البحث ينكسر بلا إنذار ويخالف شروطها. فالجدول هنا يعدّله
   المالك متى شاء، وبنية الملفّ تجعل وصل مزوّد حيّ لاحقاً
   تغييراً في دالّة واحدة (rate) لا في الصفحات.

   أهمّ ثلاثين عملة (بطلب المالك). الأساس: 1 ريال = كم من
   العملة. راجِعْها كلّ حين — الأسعار تتحرّك. */
(function (global) {
  "use strict";

  var STORE_KEY = "sf_currency";
  var BASE = "SAR";

  /* آخر مراجعة: 2026-09-08. القيمة = كم وحدة من هذه العملة
     يساوي ريالاً واحداً. الريال مربوط بالدولار عند 3.75،
     فسعره ثابت عمليّاً؛ وبقيّة العملات تتحرّك. */
  var TABLE = {
    SAR: { rate: 1,        ar: "ريال سعودي",      en: "Saudi Riyal",        sym: "﷼", dec: 2 },
    USD: { rate: 0.2667,   ar: "دولار أمريكي",    en: "US Dollar",          sym: "$",      dec: 2 },
    EUR: { rate: 0.2453,   ar: "يورو",            en: "Euro",               sym: "€",      dec: 2 },
    GBP: { rate: 0.2088,   ar: "جنيه إسترليني",   en: "British Pound",      sym: "£",      dec: 2 },
    AED: { rate: 0.9793,   ar: "درهم إماراتي",    en: "UAE Dirham",         sym: "د.إ",    dec: 2 },
    KWD: { rate: 0.0817,   ar: "دينار كويتي",     en: "Kuwaiti Dinar",      sym: "د.ك",    dec: 3 },
    QAR: { rate: 0.9709,   ar: "ريال قطري",       en: "Qatari Riyal",       sym: "ر.ق",    dec: 2 },
    BHD: { rate: 0.1005,   ar: "دينار بحريني",    en: "Bahraini Dinar",     sym: "د.ب",    dec: 3 },
    OMR: { rate: 0.1027,   ar: "ريال عُماني",     en: "Omani Rial",         sym: "ر.ع",    dec: 3 },
    EGP: { rate: 12.95,    ar: "جنيه مصري",       en: "Egyptian Pound",     sym: "ج.م",    dec: 2 },
    JOD: { rate: 0.1891,   ar: "دينار أردني",     en: "Jordanian Dinar",    sym: "د.أ",    dec: 3 },
    TRY: { rate: 10.92,    ar: "ليرة تركية",      en: "Turkish Lira",       sym: "₺",      dec: 2 },
    CNY: { rate: 1.897,    ar: "يوان صيني",       en: "Chinese Yuan",       sym: "¥",      dec: 2 },
    INR: { rate: 23.52,    ar: "روبية هندية",     en: "Indian Rupee",       sym: "₹",      dec: 2 },
    PKR: { rate: 74.85,    ar: "روبية باكستانية", en: "Pakistani Rupee",    sym: "₨",      dec: 0 },
    BDT: { rate: 32.28,    ar: "تاكا بنغلاديشي",  en: "Bangladeshi Taka",   sym: "৳",      dec: 0 },
    IDR: { rate: 4355,     ar: "روبية إندونيسية", en: "Indonesian Rupiah",  sym: "Rp",     dec: 0 },
    MYR: { rate: 1.124,    ar: "رنغيت ماليزي",    en: "Malaysian Ringgit",  sym: "RM",     dec: 2 },
    JPY: { rate: 39.45,    ar: "ين ياباني",       en: "Japanese Yen",       sym: "¥",      dec: 0 },
    KRW: { rate: 361.2,    ar: "وون كوري",        en: "South Korean Won",   sym: "₩",      dec: 0 },
    CHF: { rate: 0.2131,   ar: "فرنك سويسري",     en: "Swiss Franc",        sym: "Fr",     dec: 2 },
    CAD: { rate: 0.3648,   ar: "دولار كندي",      en: "Canadian Dollar",    sym: "C$",     dec: 2 },
    AUD: { rate: 0.4021,   ar: "دولار أسترالي",   en: "Australian Dollar",  sym: "A$",     dec: 2 },
    RUB: { rate: 21.34,    ar: "روبل روسي",       en: "Russian Ruble",      sym: "₽",      dec: 2 },
    ZAR: { rate: 4.712,    ar: "راند جنوب أفريقي", en: "South African Rand", sym: "R",     dec: 2 },
    NGN: { rate: 398.6,    ar: "نايرا نيجيري",    en: "Nigerian Naira",     sym: "₦",      dec: 0 },
    MAD: { rate: 2.451,    ar: "درهم مغربي",      en: "Moroccan Dirham",    sym: "د.م",    dec: 2 },
    TND: { rate: 0.8194,   ar: "دينار تونسي",     en: "Tunisian Dinar",     sym: "د.ت",    dec: 3 },
    SGD: { rate: 0.3417,   ar: "دولار سنغافوري",  en: "Singapore Dollar",   sym: "S$",     dec: 2 },
    BRL: { rate: 1.428,    ar: "ريال برازيلي",    en: "Brazilian Real",     sym: "R$",     dec: 2 }
  };

  var current = BASE;

  try {
    var saved = global.localStorage && localStorage.getItem(STORE_KEY);
    if (saved && TABLE[saved]) current = saved;
  } catch (e) { /* الوضع الخاصّ يمنع التخزين — يبقى الريال */ }

  function getCode() { return current; }

  function info(code) { return TABLE[code] || TABLE[BASE]; }

  function list() {
    var out = [];
    for (var k in TABLE) {
      if (Object.prototype.hasOwnProperty.call(TABLE, k)) {
        out.push({ code: k, ar: TABLE[k].ar, en: TABLE[k].en, sym: TABLE[k].sym });
      }
    }
    return out;
  }

  /* تحويل مبلغ بالريال إلى العملة الحالية. */
  function convert(sarValue) {
    var n = Number(sarValue);
    if (!isFinite(n)) return null;
    return n * info(current).rate;
  }

  /* تنسيق الرقم بفواصل الآلاف وبعدد الكسور المناسب لكلّ
     عملة: الين والوون بلا كسور، والدينار الكويتي بثلاثة. */
  function formatNumber(value, code) {
    var meta = info(code || current);
    var n = Number(value);
    if (!isFinite(n)) return "";
    try {
      return n.toLocaleString(undefined, {
        minimumFractionDigits: meta.dec,
        maximumFractionDigits: meta.dec
      });
    } catch (e) {
      return n.toFixed(meta.dec);
    }
  }

  function setCode(code) {
    if (!TABLE[code]) return false;
    current = code;
    try {
      if (global.localStorage) localStorage.setItem(STORE_KEY, code);
    } catch (e) { /* لا يمنع التغيير */ }
    return true;
  }

  /* هل المعروض عملة أجنبية؟ الصفحات تستعمله لتُظهر
     تنبيه «يُحاسَب بالريال» عند الدفع. */
  function isForeign() { return current !== BASE; }

  global.SFCurrency = {
    BASE: BASE,
    getCode: getCode,
    setCode: setCode,
    list: list,
    info: info,
    convert: convert,
    formatNumber: formatNumber,
    isForeign: isForeign
  };
})(window);
