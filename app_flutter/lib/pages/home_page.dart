// ============================================================
//  الرئيسية — مقابل app-home.html
//
//  البيانات حقيقية من القاعدة: الفئات ثم المنتجات الأكثر
//  مبيعاً. مولّدات البيانات الوهمية القديمة لم تُنقل عمداً.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/factory_service.dart';
import '../widgets/common.dart';
import '../widgets/wordmark.dart';
import 'factories_page.dart';
import 'product_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<SFProduct>> _products;

  @override
  void initState() {
    super.initState();
    _products = FactoryService.latestProducts(limit: 24);
  }

  Future<void> _reload() async {
    setState(() {
      _products = FactoryService.latestProducts(limit: 24);
    });
    await _products;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(
        searchHint: i18n.t('search_placeholder'),
        onSearchSubmitted: (q) {
          if (q.trim().isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FactoriesPage(initialSearch: q.trim()),
            ),
          );
        },
        actions: const [
          Padding(
            padding: EdgeInsets.only(left: 8, right: 8),
            child: Center(child: Wordmark(fontSize: 10, width: 96)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: SFColors.midGreen,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            _CategoriesStrip(),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                i18n.t('home_bestsellers'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FutureBuilder<List<SFProduct>>(
              future: _products,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return SFStateView(
                    message: i18n.t('fx_loading'),
                    loading: true,
                  );
                }
                if (snap.hasError) {
                  return SFStateView(
                    message: i18n.t('fx_failed'),
                    icon: Icons.cloud_off,
                    onRetry: _reload,
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return SFStateView(message: i18n.t('fx_empty'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _ProductCard(product: items[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط الفئات الأفقي — الضغط يفتح قائمة المصانع مصفّاة.
class _CategoriesStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final cat = cats[i];
          return InkWell(
            onTap: () {
              // مفتاح الربط هو الاسم الإنجليزي — هو ما يخزّنه
              // عمود industry في القاعدة.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FactoriesPage(
                    initialCategory: i18n.categoryKey(cat),
                    categoryLabel: i18n.categoryName(cat),
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(SFMetrics.radius),
            child: Container(
              width: 104,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SFColors.white,
                border: Border.all(color: SFColors.border),
                borderRadius: BorderRadius.circular(SFMetrics.radius),
              ),
              child: Center(
                child: Text(
                  i18n.categoryName(cat),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final SFProduct product;

  @override
  Widget build(BuildContext context) {
    final factoryName =
        (product.raw['factories'] as Map?)?['name'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductPage(product: product),
          ),
        );
      },
      borderRadius: BorderRadius.circular(SFMetrics.radius),
      child: Container(
        decoration: BoxDecoration(
          color: SFColors.white,
          border: Border.all(color: SFColors.border),
          borderRadius: BorderRadius.circular(SFMetrics.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SFImage(
                url: product.image,
                radius: SFMetrics.radius,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (factoryName.isNotEmpty)
                    Text(
                      factoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SFColors.muted2,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (product.price > 0)
                    Text(
                      '${product.price.toStringAsFixed(2)} ر.س',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: SFColors.midGreen,
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
