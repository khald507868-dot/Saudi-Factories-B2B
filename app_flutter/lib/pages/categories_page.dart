// ============================================================
//  الفئات — كانت درجاً منسدلاً في app-home.html
//
//  صارت قسماً مستقلاً في الشريط السفلي: القائمة نفسها
//  (عشرون فئة) والضغط يفتح المصانع مصفّاة بالفئة.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'factories_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('drawer_categories_title')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final cat = cats[i];
          return InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FactoriesPage(
                  // الاسم الإنجليزي هو مفتاح الربط مع عمود industry.
                  initialCategory: i18n.categoryKey(cat),
                  categoryLabel: i18n.categoryName(cat),
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(SFMetrics.radius),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: SFColors.white,
                border: Border.all(color: SFColors.border),
                borderRadius: BorderRadius.circular(SFMetrics.radius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      i18n.categoryName(cat),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
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
        },
      ),
    );
  }
}
