// ============================================================
//  بوابة نوع الحساب — مقابل app-user-type.html
//
//  الاختيار هنا يحدّد شكل شاشة التسجيل بعده (فرد أم مصنع).
//  ملاحظة: هذا اختيار واجهة فقط — النوع الحقيقي يُكتب في
//  user metadata عند التسجيل، ومُشغّل القاعدة هو من يعتمده،
//  والحارس يمنع تغييره لاحقاً.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/wordmark.dart';
import 'auth_page.dart';

class UserTypePage extends StatelessWidget {
  const UserTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.darkGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Wordmark(fontSize: 22, width: 220),
              const SizedBox(height: 36),
              Text(
                i18n.t('usertype_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SFColors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                i18n.t('usertype_subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SFColors.muted,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 34),
              _TypeCard(
                icon: Icons.person_outline,
                label: i18n.t('usertype_individual'),
                onTap: () => _go(context, 'individual'),
              ),
              const SizedBox(height: 14),
              _TypeCard(
                icon: Icons.factory_outlined,
                label: i18n.t('usertype_factory'),
                onTap: () => _go(context, 'factory'),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, String accountType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthPage(accountType: accountType),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SFMetrics.radius),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          color: SFColors.white.withValues(alpha: 0.06),
          border: Border.all(color: SFColors.green, width: 1.4),
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        child: Row(
          children: [
            Icon(icon, color: SFColors.green, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: SFColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right,
              color: SFColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
