// ============================================================
//  المساعدة والدعم — مقابل app-help.html
//
//  صفحة ثابتة بلا قاعدة بيانات، عمداً: يجب أن تفتح لمن لا
//  يستطيع تسجيل الدخول أصلاً.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(title: Text(i18n.t('help_page_heading'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            i18n.t('help_contact_title'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          const _ContactRow(
            icon: Icons.phone_outlined,
            labelKey: 'help_phone_main_label',
            value: '920000000',
          ),
          const _ContactRow(
            icon: Icons.support_agent_outlined,
            labelKey: 'help_phone_support_label',
            value: '920000001',
          ),
          const _ContactRow(
            icon: Icons.mail_outline,
            labelKey: 'help_email_label',
            value: 'support@saudifactories.sa',
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.labelKey,
    required this.value,
  });

  final IconData icon;
  final String labelKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SFColors.white,
          border: Border.all(color: SFColors.border),
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        child: Row(
          children: [
            Icon(icon, color: SFColors.midGreen, size: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(labelKey),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SFColors.muted2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // القيمة لاتينية دائماً فيُثبَّت اتجاهها حتى لا
                  // ينعكس ترتيب الأرقام في العربية.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
