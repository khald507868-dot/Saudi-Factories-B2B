// ============================================================
//  اختبارات وحدة لطبقة الترجمة
//
//  لا نختبر الواجهة هنا: بناؤها يتطلّب اتصالاً بـ Supabase.
//  ما يُختبر هو المنطق الخالص الذي يسهل أن ينكسر بصمت —
//  سلسلة احتياط الترجمة، واتجاه الكتابة، وتطابق منتقي اللغات
//  مع جدول الترجمة (لغة في المنتقي بلا ترجمة تظهر إنجليزية
//  وتبدو معطوبة).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/core/i18n_data.dart';
import 'package:saudi_factories/pages/settings_page.dart';

void main() {
  group('جدول الترجمة', () {
    test('اللغات الثلاثون موجودة', () {
      expect(kDict.length, 30);
      expect(kDict.containsKey('ar'), isTrue);
      expect(kDict.containsKey('en'), isTrue);
    });

    test('كل لغة تحمل نفس عدد مفاتيح العربية', () {
      final expected = kDict['ar']!.length;
      for (final entry in kDict.entries) {
        expect(entry.value.length, expected,
            reason: 'اللغة ${entry.key} ينقصها مفاتيح');
      }
    });

    test('الفئات عشرون والمناطق ثلاث عشرة', () {
      expect(kCategories.length, 20);
      expect(kRegionNames.length, 13);
    });
  });

  group('سلوك I18n', () {
    test('الترجمة ترجع نص اللغة الحالية', () {
      final i18n = I18n('ar');
      expect(i18n.t('nav_home'), kDict['ar']!['nav_home']);
    });

    test('مفتاح غير موجود يرجع نفسه', () {
      final i18n = I18n('ar');
      expect(i18n.t('__no_such_key__'), '__no_such_key__');
    });

    test('العربية من اليمين والإنجليزية من اليسار', () {
      expect(I18n('ar').direction, TextDirection.rtl);
      expect(I18n('he').direction, TextDirection.rtl);
      expect(I18n('en').direction, TextDirection.ltr);
      expect(I18n('fr').direction, TextDirection.ltr);
    });

    test('مفتاح الفئة هو الاسم الإنجليزي — مفتاح الربط مع industry', () {
      final i18n = I18n('ar');
      final cat = kCategories.first;
      expect(i18n.categoryKey(cat), cat['en']);
      expect(i18n.categoryName(cat), cat['ar']);
    });

    test('اسم المنطقة يتبع اللغة', () {
      expect(I18n('ar').regionName('ryiadh'), 'الرياض');
      expect(I18n('en').regionName('ryiadh'), 'Riyadh');
      expect(I18n('en').regionName('unknown'), 'unknown');
    });
  });

  test('كل لغة في المنتقي لها ترجمة', () {
    expect(languagePickerIsConsistent(), isTrue);
    for (final code in kLanguagePicker.keys) {
      expect(kDict.containsKey(code), isTrue, reason: 'لا ترجمة للغة $code');
    }
  });

  test('رمز العلم يُبنى من رمز الدولة', () {
    expect(flagEmoji('SA'), '🇸🇦');
    expect(flagEmoji('GB'), '🇬🇧');
  });
}
