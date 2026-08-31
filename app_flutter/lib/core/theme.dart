// ============================================================
//  ألوان التطبيق وثيمه
//
//  الألوان منقولة حرفياً من صفحات app-*.html حتى يبقى شكل
//  التطبيق مطابقاً للنسخة القديمة. لا تغيّرها إلا بطلب المالك.
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// لوحة ألوان المشروع — الأسماء كما وردت في CSS الأصلي.
class SFColors {
  /// الأخضر الداكن: الشريط العلوي والسفلي والنص الأساسي.
  static const Color darkGreen = Color(0xFF04361B);

  /// خلفية الصفحات.
  static const Color pageBg = Color(0xFFF3F5F3);

  /// الأخضر الفاتح — التمييز والروابط النشطة.
  static const Color green = Color(0xFF45A06A);

  /// أخضر متوسط — التدرّجات.
  static const Color midGreen = Color(0xFF1F6B42);

  /// ذهبي — شارة B2B.
  static const Color gold = Color(0xFFC9A227);

  /// رمادي النص الثانوي.
  static const Color muted = Color(0xFF9AA8A0);

  /// رمادي أغمق قليلاً للنص الثانوي المهم.
  static const Color muted2 = Color(0xFF6B7D70);

  /// أخضر باهت للنص المساعد.
  static const Color softGreen = Color(0xFF5C8A70);

  /// حدود البطاقات والفواصل.
  static const Color border = Color(0xFFE2E6E3);

  /// خلفية بديلة فاتحة.
  static const Color surfaceAlt = Color(0xFFEEF1EE);

  /// أحمر الخطأ والحذف.
  static const Color danger = Color(0xFFD93025);

  /// خلفية رسالة الخطأ.
  static const Color dangerBg = Color(0xFFFDECEA);

  static const Color white = Color(0xFFFFFFFF);
}

/// ارتفاعات ثابتة منقولة من mobile.css — الشريط السفلي 52 بكسل.
class SFMetrics {
  static const double bottomNavHeight = 52;
  static const double topBarHeight = 58;
  static const double radius = 12;
  static const double pagePadding = 16;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SFColors.darkGreen,
      primary: SFColors.darkGreen,
      secondary: SFColors.green,
      surface: SFColors.white,
      error: SFColors.danger,
    ),
    scaffoldBackgroundColor: SFColors.pageBg,
  );

  // الخط Tajawal — نفس الخط الذي يفرضه green-frames.css على الويب.
  final textTheme = GoogleFonts.tajawalTextTheme(base.textTheme).apply(
    bodyColor: SFColors.darkGreen,
    displayColor: SFColors.darkGreen,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: SFColors.darkGreen,
      foregroundColor: SFColors.white,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SFColors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        borderSide: const BorderSide(color: SFColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        borderSide: const BorderSide(color: SFColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        borderSide: const BorderSide(color: SFColors.green, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SFColors.darkGreen,
        foregroundColor: SFColors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        textStyle: GoogleFonts.tajawal(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: SFColors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        side: const BorderSide(color: SFColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: SFColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}
