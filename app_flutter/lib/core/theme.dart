// ============================================================
//  ألوان التطبيق وثيمه
//
//  ألوان صفحات الويب الحالية: desktop.css وgreen-frames.css.
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// لوحة ألوان المشروع — الأسماء كما وردت في CSS الأصلي.
class SFColors {
  /// الأخضر الداكن للهوية والعناوين.
  static const Color darkGreen = Color(0xFF04361B);

  /// خلفية الصفحات.
  static const Color pageBg = Color(0xFFF6F7F6);

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

  /// حدود البطاقات الخضراء نفسها في green-frames.css.
  static const Color border = Color(0xFFC7DFCE);
  /// أخضر إطار البحث حسب المرجع المرئي.
  static const Color searchBorder = Color(0xFF3D7047);
  static const Color divider = Color(0xFFE6EBE8);
  static const Color text = Color(0xFF12331D);
  static const Color selected = Color(0xFFE6F2EA);

  /// خلفية بديلة فاتحة.
  static const Color surfaceAlt = Color(0xFFF4F8F5);

  /// أحمر الخطأ والحذف.
  static const Color danger = Color(0xFFD93025);

  /// خلفية رسالة الخطأ.
  static const Color dangerBg = Color(0xFFFDECEA);

  static const Color white = Color(0xFFFFFFFF);
}

/// قياسات مريحة للجوال، مستقلة عن تخطيط سطح المكتب.
class SFMetrics {
  static const double bottomNavHeight = 50;
  static const double topBarHeight = 56;
  static const double radius = 12;
  static const double pagePadding = 16;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: SFColors.midGreen,
      onPrimary: SFColors.white,
      primaryContainer: SFColors.selected,
      onPrimaryContainer: SFColors.darkGreen,
      secondary: SFColors.midGreen,
      onSecondary: SFColors.white,
      secondaryContainer: SFColors.selected,
      onSecondaryContainer: SFColors.darkGreen,
      surface: SFColors.white,
      onSurface: SFColors.text,
      onSurfaceVariant: SFColors.muted2,
      surfaceContainerLowest: SFColors.white,
      surfaceContainerLow: SFColors.surfaceAlt,
      surfaceContainer: SFColors.surfaceAlt,
      surfaceContainerHigh: SFColors.selected,
      surfaceContainerHighest: SFColors.selected,
      outline: SFColors.border,
      outlineVariant: SFColors.divider,
      error: SFColors.danger,
      onError: SFColors.white,
      surfaceTint: Colors.transparent,
    ),
    scaffoldBackgroundColor: SFColors.pageBg,
  );

  // الخط Tajawal — نفس الخط الذي يفرضه green-frames.css على الويب.
  final textTheme = GoogleFonts.tajawalTextTheme(base.textTheme)
      .apply(bodyColor: SFColors.text, displayColor: SFColors.darkGreen)
      .copyWith(
        bodyMedium: GoogleFonts.tajawal(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: SFColors.text,
        ),
        bodyLarge: GoogleFonts.tajawal(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: SFColors.text,
        ),
        titleMedium: GoogleFonts.tajawal(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: SFColors.darkGreen,
        ),
        titleLarge: GoogleFonts.tajawal(
          fontSize: 19,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: SFColors.darkGreen,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: SFColors.white,
      foregroundColor: SFColors.darkGreen,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: SFMetrics.topBarHeight,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: SFColors.divider)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SFColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        backgroundColor: SFColors.midGreen,
        foregroundColor: SFColors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        textStyle: GoogleFonts.tajawal(
          fontSize: 15,
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
      color: SFColors.divider,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: SFColors.midGreen,
      textColor: SFColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: SFColors.midGreen,
      unselectedLabelColor: SFColors.muted2,
      indicatorColor: SFColors.midGreen,
      dividerColor: SFColors.divider,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: SFColors.white,
      selectedColor: SFColors.selected,
      side: const BorderSide(color: SFColors.border),
      labelStyle: GoogleFonts.tajawal(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: SFColors.darkGreen,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SFColors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: SFColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SFColors.white,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
