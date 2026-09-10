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
import 'core/currency.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'pages/splash_page.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  final i18n = await I18n.load();
  await SFCurrency.instance.load();
  // إبلاغ الصفحات التي تعتمد على I18nScope بتغيّر عملة العرض أيضاً.
  SFCurrency.instance.addListener(i18n.refreshDisplay);
  // يُقرأ المستخدم فورًا، ويُحمّل ملفه أثناء عرض الترحيب ذي الثلاث ثوانٍ.
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
            supportedLocales: const [Locale('ar'), Locale('en')],
            localeResolutionCallback: (_, _) =>
                Locale(i18n.lang == 'ar' ? 'ar' : 'en'),
            builder: (context, child) {
              // اتجاه الكتابة يتبع اللغة المختارة، لا لغة الجهاز.
              return Directionality(
                textDirection: i18n.direction,
                child: PhoneColumn(child: child ?? const SizedBox.shrink()),
              );
            },
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}

/// يحصر التطبيق في عمود بعرض الجوال ويتوسّطه على الشاشة العريضة.
///
/// هذا مقابل قاعدة "عمود الجوال" في mobile.css: التطبيق عمودي
/// التصميم، فتمديده على شاشة لابتوب يجعل الأزرار شريطاً ممتداً
/// من حافة إلى حافة ولا يشبه الجوال إطلاقاً.
///
/// على الجوال الحقيقي لا يفعل هذا شيئاً — العرض أصلاً أضيق من
/// الحدّ، فيمرّ الطفل كما هو.
class PhoneColumn extends StatelessWidget {
  const PhoneColumn({super.key, required this.child});

  final Widget child;

  /// نفس عرض عمود الجوال في mobile.css.
  static const double maxWidth = 430;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= maxWidth) return child;

    return ColoredBox(
      // خلفية المعاينة من صفحة الويب نفسها دون مساحات خضراء داكنة.
      color: SFColors.pageBg,
      child: Center(
        child: ClipRect(
          // سطح مستقل يمنع تمويه الأشرطة من سحب الهامش الأبيض الخارجي.
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: SizedBox(
            width: maxWidth,
            child: DecoratedBox(
              // فوق محتوى المسارات كي تبقى الحدود ظاهرة على كل الصفحات.
              position: DecorationPosition.foreground,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: SFColors.border),
                  right: BorderSide(color: SFColors.border),
                ),
              ),
              child: MediaQuery(
                // مهم: يجب تصحيح عرض MediaQuery أيضاً، وإلا ظلّت
                // الشاشات تحسب تخطيطها على عرض النافذة الكامل
                // (مثل شبكة المنتجات) وهي داخل عمود ضيّق.
                data: MediaQuery.of(context).copyWith(
                  size: Size(maxWidth, MediaQuery.sizeOf(context).height),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
