// ============================================================
//  الرئيسية — مقابل app-home.html
//
//  الترتيب: الإعلانات، الفئات، أرقام المنصة، ثم المنتجات.
//  البيانات حقيقية من القاعدة.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/factory_service.dart';
import '../services/catalog_service.dart';
import '../services/auth_service.dart';
import '../services/promotion_service.dart';
import '../services/delivery_address_service.dart';
import '../widgets/catalog_product_card.dart';
import '../widgets/common.dart';
import '../widgets/delivery_address_widgets.dart';
import '../widgets/platform_stats.dart';
import '../widgets/home_promotions.dart';
import '../widgets/promotion_image_appearance.dart';
import 'admin_page.dart';
import 'factories_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<SFProduct>> _products;
  late Future<Map<String, String>> _categoryImages;
  late Future<List<SFPromotion>> _promotions;
  Color _promotionBackground = SFColors.white;

  void _updatePromotionBackground(Color color) {
    if (mounted && _promotionBackground != color) {
      setState(() => _promotionBackground = color);
    }
  }

  @override
  void initState() {
    super.initState();
    _products = FactoryService.latestProducts(limit: 24);
    _categoryImages = CatalogService.categoryImages();
    _promotions = PromotionService.listPublic();
    PromotionService.changes.addListener(_reloadPromotions);
  }

  void _reloadPromotions() {
    if (mounted) {
      setState(() {
        _promotions = PromotionService.listPublic();
      });
    }
  }

  @override
  void dispose() {
    PromotionService.changes.removeListener(_reloadPromotions);
    super.dispose();
  }

  Future<void> _managePromotions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminPage(initialSection: 'promotions'),
      ),
    );
    _reloadPromotions();
  }

  Future<void> _reload() async {
    DeliveryAddressService.instance.reload();
    setState(() {
      _products = FactoryService.latestProducts(limit: 24);
      _categoryImages = CatalogService.categoryImages();
      _promotions = PromotionService.listPublic();
    });
    await _products;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(
        compact: true,
        toolbarHeight: 44,
        backgroundColor: _promotionBackground,
        searchBackgroundColor: SFColors.white,
        showBottomBorder: false,
        titleWidget: DeliveryAddressHeader(
          foregroundColor: promotionHeaderForeground(_promotionBackground),
        ),
        searchHint: i18n.t('search_placeholder'),
        onSearchSubmitted: (q) {
          if (q.trim().isEmpty) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FactoriesPage(initialSearch: q.trim()),
            ),
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: SFColors.midGreen,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ListenableBuilder(
              listenable: AuthService.instance,
              builder: (context, _) => HomePromotions(
                promotions: _promotions,
                onRetry: _reloadPromotions,
                onBackgroundColorChanged: _updatePromotionBackground,
                onManage: AuthService.instance.profile?.isAdmin == true
                    ? _managePromotions
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t('drawer_categories_title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            FutureBuilder<Map<String, String>>(
              future: _categoryImages,
              builder: (_, snapshot) =>
                  _CategoriesStrip(images: snapshot.data ?? {}),
            ),
            const SizedBox(height: 24),
            const PlatformStats(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                i18n.t('home_bestsellers'),
                style: const TextStyle(
                  fontSize: 16,
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
                  return SFStateView(message: i18n.t('factory_no_products'));
                }
                return LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent:
                          (constraints.maxWidth - 44) / 2 / 1.18 + 118,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        CatalogProductCard(product: items[i]),
                  ),
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
  const _CategoriesStrip({required this.images});
  final Map<String, String> images;
  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;

    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
              width: 110,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SFColors.surfaceAlt,
                border: Border.all(color: SFColors.border),
                borderRadius: BorderRadius.circular(SFMetrics.radius),
              ),
              child: Column(
                children: [
                  SFImage(
                    url: images[i18n.categoryKey(cat)] ?? '',
                    width: 48,
                    height: 48,
                    radius: 12,
                    placeholderIcon: Icons.category_outlined,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      i18n.categoryName(cat),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
