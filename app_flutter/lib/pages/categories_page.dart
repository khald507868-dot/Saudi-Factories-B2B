// ============================================================
//  الفئات — كانت درجاً منسدلاً في app-home.html
//
//  صارت قسماً مستقلاً في الشريط السفلي: القائمة نفسها
//  (عشرون فئة) والضغط يفتح المصانع مصفّاة بالفئة.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/catalog_service.dart';
import '../widgets/common.dart';
import 'factories_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late Future<Map<String, String>> _images = CatalogService.categoryImages();

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('drawer_categories_title')),
      body: FutureBuilder<Map<String, String>>(
        future: _images,
        builder: (context, snapshot) => RefreshIndicator(
          onRefresh: () async {
            setState(() => _images = CatalogService.categoryImages());
            await _images;
          },
          child: LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: cats.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth >= 400 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 148,
              ),
              itemBuilder: (context, i) {
                final cat = cats[i];
                return Material(
                  color: SFColors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SFMetrics.radius),
                    side: const BorderSide(color: SFColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
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
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          SFImage(
                            url: snapshot.data?[i18n.categoryKey(cat)] ?? '',
                            width: 62,
                            height: 62,
                            radius: 12,
                            placeholderIcon: Icons.category_outlined,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              i18n.categoryName(cat),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
