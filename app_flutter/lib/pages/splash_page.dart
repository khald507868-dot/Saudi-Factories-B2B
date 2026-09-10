// ============================================================
//  ترحيب متحرك لمدة ثلاث ثوانٍ عند فتح التطبيق.
//  بعده ينتقل الزائر لاختيار الحساب والمسجّل إلى الرئيسية.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/factory_welcome_illustration.dart';
import '../widgets/wordmark.dart';
import 'shell.dart';
import 'user_type_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const displayDuration = Duration(seconds: 3);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final Animation<double> _introOpacity;
  late final Animation<Offset> _introOffset;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: SplashPage.displayDuration,
    );
    final entrance = CurvedAnimation(
      parent: _animation,
      curve: const Interval(0, 0.2, curve: Curves.easeOutCubic),
    );
    _introOpacity = Tween<double>(begin: 0, end: 1).animate(entrance);
    _introOffset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(entrance);

    // يبدأ العدّ بعد ظهور أول إطار؛ تقليل الحركة لا يختصر مدة الترحيب.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animation.forward();
      _timer = Timer(SplashPage.displayDuration, _openNextPage);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  void _openNextPage() {
    if (!mounted || _leaving) return;
    _leaving = true;
    // الجلسة تُستعاد قبل runApp، وstart يقرأ المستخدم قبل تحميل الملف.
    // لا نربط الثلاث ثوانٍ بزمن الشبكة الخاص ببيانات الملف الشخصي.
    final signedIn = AuthService.instance.isSignedIn;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) =>
            signedIn ? const AppShell() : const UserTypePage(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sceneAnimation = reduceMotion
        ? const AlwaysStoppedAnimation<double>(0.55)
        : _animation;

    return Scaffold(
      backgroundColor: SFColors.surfaceAlt,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SFColors.white, SFColors.surfaceAlt, SFColors.selected],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: reduceMotion
                          ? const AlwaysStoppedAnimation(1.0)
                          : _introOpacity,
                      child: SlideTransition(
                        position: reduceMotion
                            ? const AlwaysStoppedAnimation(Offset.zero)
                            : _introOffset,
                        child: const Wordmark(fontSize: 27, width: 286),
                      ),
                    ),
                    const SizedBox(height: 36),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: FactoryWelcomeIllustration(
                        animation: sceneAnimation,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: Text(
                        context.t('splash_tagline'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SFColors.darkGreen,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
