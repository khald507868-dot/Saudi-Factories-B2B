// ============================================================
//  نقطة انطلاق التطبيق
//
//  هذه نسخة Flutter من صفحات app-*.html. صفحات web- تبقى
//  كما هي للمتصفّح، والاثنان يقرآن نفس قاعدة بيانات Supabase.
//
//  ترتيب الإقلاع: تهيئة Supabase ← قراءة اللغة المحفوظة ←
//  قراءة الجلسة ← عرض الواجهة.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'pages/splash_page.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  final i18n = await I18n.load();
  // لا ننتظر اكتمال قراءة الملف الشخصي — شاشة البداية تنتظرها.
  AuthService.instance.start();
  runApp(SaudiFactoriesApp(i18n: i18n));
}

class SaudiFactoriesApp extends StatelessWidget {
  const SaudiFactoriesApp({super.key, required this.i18n});

  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return I18nScope(
      i18n: i18n,
      child: AnimatedBuilder(
        animation: i18n,
        builder: (context, _) {
          return MaterialApp(
            title: i18n.t('app_title'),
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: i18n.locale,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // كل اللغات الثلاثين مدعومة نصّياً؛ ما لا تعرفه Flutter
            // من ترجمات النظام يعود للإنجليزية، والنصوص كلها من عندنا.
            supportedLocales: const [
              Locale('ar'),
              Locale('en'),
            ],
            localeResolutionCallback: (_, _) => i18n.locale,
            builder: (context, child) {
              // اتجاه الكتابة يتبع اللغة المختارة، لا لغة الجهاز.
              return Directionality(
                textDirection: i18n.direction,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}
