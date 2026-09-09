// ============================================================
//  شاشة البداية — مقابل app-index.html
//
//  تنتظر قراءة الجلسة ثم تقرّر: المسجّل يدخل مباشرة،
//  وغير المسجّل يرى بوابة نوع الحساب.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/wordmark.dart';
import 'shell.dart';
import 'user_type_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // إنظار إطار واحد قبل أي تنقّل.
    //
    // لو كان AuthService جاهزاً أصلاً لما انتظرت الحلقة تحته
    // ولجرى pushReplacement داخل initState والـ Navigator
    // لا يزال يُبنى، فينفجر:
    //   Assertion failed: !navigator._debugLocked
    // وتبقى الشاشة على شاشة البداية.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    // مهلة قصيرة حتى يقرأ AuthService الجلسة المحفوظة.
    final auth = AuthService.instance;
    var waited = 0;
    while (!auth.ready && waited < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      waited += 50;
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            auth.isSignedIn ? const AppShell() : const UserTypePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Wordmark(fontSize: 24, width: 250, onDark: false),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                i18n.t('splash_tagline'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SFColors.muted2,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                color: SFColors.midGreen,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
