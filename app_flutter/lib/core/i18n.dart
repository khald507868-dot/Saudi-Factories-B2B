// ============================================================
//  الترجمة واتجاه الكتابة — مقابل i18n.js في نسخة الويب
//
//  سلسلة الاحتياط نفسها: dict[lang][key] ← dict.en[key]
//  ← dict.ar[key] ← key. وتغيير اللغة يعيد بناء الواجهة كلها
//  (بدل إعادة تحميل الصفحة كما في الويب).
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_data.dart';

const String _kLangKey = 'sf_lang';

/// حالة اللغة — تُوفَّر عبر [I18nScope] وتُبنى مرة واحدة في main.
class I18n extends ChangeNotifier {
  I18n(this._lang);

  String _lang;

  String get lang => _lang;

  /// اتجاه الكتابة للّغة الحالية.
  TextDirection get direction =>
      kRtlLangs.contains(_lang) ? TextDirection.rtl : TextDirection.ltr;

  bool get isRtl => direction == TextDirection.rtl;

  Locale get locale => Locale(_lang);

  /// يقرأ اللغة المحفوظة، والافتراضي العربية.
  static Future<I18n> load() async {
    String lang = 'ar';
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kLangKey);
      if (saved != null && kDict.containsKey(saved)) lang = saved;
    } catch (_) {
      // تعذّر القراءة — نبقى على العربية.
    }
    return I18n(lang);
  }

  Future<void> setLang(String code) async {
    if (!kDict.containsKey(code) || code == _lang) return;
    _lang = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLangKey, code);
    } catch (_) {
      // الحفظ فشل — اللغة تبقى فعّالة لهذه الجلسة فقط.
    }
  }

  /// ترجمة مفتاح — بنفس سلسلة احتياط نسخة الويب.
  String t(String key) {
    return kDict[_lang]?[key] ??
        kDict['en']?[key] ??
        kDict['ar']?[key] ??
        key;
  }

  /// اسم منطقة باللغة الحالية.
  String regionName(String id) {
    final r = kRegionNames[id];
    if (r == null) return id;
    return r[_lang] ?? r['en'] ?? r['ar'] ?? id;
  }

  /// اسم فئة باللغة الحالية.
  String categoryName(Map<String, String> cat) {
    return cat[_lang] ?? cat['en'] ?? cat['ar'] ?? '';
  }

  /// الفئات — قائمة، تماماً كما في الويب.
  List<Map<String, String>> get categories => kCategories;

  /// اسم الفئة بالإنجليزية: مفتاح الربط مع عمود industry في القاعدة.
  /// انظر ملاحظة "مفتاح الربط" في CLAUDE.md — لا تستخدم الاسم العربي.
  String categoryKey(Map<String, String> cat) => cat['en'] ?? '';
}

/// يتيح الوصول إلى [I18n] من أي widget عبر `I18nScope.of(context)`.
class I18nScope extends InheritedNotifier<I18n> {
  const I18nScope({
    super.key,
    required I18n i18n,
    required super.child,
  }) : super(notifier: i18n);

  static I18n of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(scope != null, 'I18nScope غير موجود فوق هذا الـ widget');
    return scope!.notifier!;
  }
}

/// اختصار مريح: `context.t('nav_home')`.
extension I18nContext on BuildContext {
  I18n get i18n => I18nScope.of(this);
  String t(String key) => I18nScope.of(this).t(key);
}
