// ============================================================
//  الرئيسية — مقابل app-home.html
//
//  الترتيب: الإعلانات، الفئات، ثم المنتجات؛ أرقام المنصة من زر الترويسة.
//  البيانات حقيقية من القاعدة.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/factory_service.dart';
import '../services/catalog_service.dart';
import '../services/auth_service.dart';
import '../services/promotion_service.dart';
import '../services/video_promotion_service.dart';
import '../services/delivery_address_service.dart';
import '../services/reviews_service.dart';
import '../widgets/common.dart';
import '../widgets/home_header.dart';
import '../widgets/platform_stats.dart';
import '../widgets/home_promotions.dart';
import '../widgets/home_video_promotions.dart';
import '../widgets/home_product_details.dart';
import '../widgets/slow_auto_scroll.dart';
import 'admin_page.dart';
import 'factories_page.dart';
import 'product_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollController = ScrollController();
  late Future<List<SFProduct>> _products;
  late Future<Map<String, String>> _categoryImages;
  late Future<List<SFPromotion>> _promotions;
  late Future<List<SFVideoPromotion>> _videoPromotions;
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
    _videoPromotions = VideoPromotionService.listPublic();
    VideoPromotionService.changes.addListener(_reloadVideoPromotions);
    PromotionService.changes.addListener(_reloadPromotions);
  }

  void _reloadVideoPromotions() {
    if (mounted) {
      setState(() => _videoPromotions = VideoPromotionService.listPublic());
    }
  }

  Future<void> _manageVideoPromotions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminPage(initialSection: 'video_ads'),
      ),
    );
    _reloadVideoPromotions();
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
    VideoPromotionService.changes.removeListener(_reloadVideoPromotions);
    PromotionService.changes.removeListener(_reloadPromotions);
    _scrollController.dispose();
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
      _videoPromotions = VideoPromotionService.listPublic();
    });
    await _products;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      extendBodyBehindAppBar: true,
      appBar: HomeHeader(
        scrollController: _scrollController,
        promotionColor: _promotionBackground,
        searchHint: i18n.t('search_placeholder'),
        onStatsPressed: () => showPlatformStats(context),
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
        edgeOffset: HomeHeader.height + MediaQuery.paddingOf(context).top,
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.only(
            top: HomeHeader.height + MediaQuery.paddingOf(context).top,
            bottom: 24 + bottomInset,
          ),
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
            ListenableBuilder(
              listenable: AuthService.instance,
              builder: (context, _) => HomeVideoPromotions(
                promotions: _videoPromotions,
                onRetry: _reloadVideoPromotions,
                onManage: AuthService.instance.profile?.isAdmin == true
                    ? _manageVideoPromotions
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                return _ProductsStrip(
                  products: items,
                  autoScrollEnabled: widget.isActive,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsStrip extends StatefulWidget {
  const _ProductsStrip({
    required this.products,
    required this.autoScrollEnabled,
  });

  final List<SFProduct> products;
  final bool autoScrollEnabled;

  @override
  State<_ProductsStrip> createState() => _ProductsStripState();
}

class _ProductsStripState extends State<_ProductsStrip> {
  late Future<Map<int, SFProductRating>> _ratings;

  void _loadRatings() {
    // طلب واحد للشريط كله، دون تأخير ظهور الصور والأسعار.
    _ratings = SFReviews.loadRatings(
      widget.products.map((product) => product.id).toList(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  @override
  void didUpdateWidget(covariant _ProductsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) _loadRatings();
  }

  Future<void> _openProduct(int index) async {
    final product = widget.products[index];
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductPage(product: product)));
    // ينعكس التقييم الذي أضيف أو عُدّل في صفحة المنتج عند الرجوع.
    if (mounted) setState(_loadRatings);
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<int, SFProductRating>>(
        future: _ratings,
        builder: (context, snapshot) => _HomeItemsStrip(
          autoScrollEnabled: widget.autoScrollEnabled,
          key: const PageStorageKey('home-products'),
          itemCount: widget.products.length,
          imageAt: (i) => widget.products[i].image,
          labelAt: (i) =>
              widget.products[i].name.isEmpty ? '—' : widget.products[i].name,
          placeholderIcon: Icons.inventory_2_outlined,
          onTap: _openProduct,
          detailsHeight: HomeProductDetails.heightFor(context),
          detailsBuilder: (context, i) => HomeProductDetails(
            product: widget.products[i],
            rating: snapshot.hasData
                ? snapshot.data![widget.products[i].id] ??
                      const SFProductRating(average: 0, count: 0)
                : null,
            ratingLoading: snapshot.connectionState != ConnectionState.done,
            ratingFailed: snapshot.hasError,
          ),
        ),
      );
}

/// شريط الفئات الأفقي — الضغط يفتح قائمة المصانع مصفّاة.
class _CategoriesStrip extends StatelessWidget {
  const _CategoriesStrip({required this.images});
  final Map<String, String> images;
  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final cats = i18n.categories;

    return _HomeItemsStrip(
      key: const PageStorageKey('home-categories'),
      itemCount: cats.length,
      imageAt: (i) => images[i18n.categoryKey(cats[i])] ?? '',
      labelAt: (i) => i18n.categoryName(cats[i]),
      placeholderIcon: Icons.category_outlined,
      onTap: (i) {
        // مفتاح الربط هو الاسم الإنجليزي المخزّن في عمود industry.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FactoriesPage(
              initialCategory: i18n.categoryKey(cats[i]),
              categoryLabel: i18n.categoryName(cats[i]),
            ),
          ),
        );
      },
    );
  }
}

/// نفس حجم الصور والإطار والاسم للفئات والمنتجات في الرئيسية.
class _HomeItemsStrip extends StatelessWidget {
  const _HomeItemsStrip({
    super.key,
    required this.itemCount,
    required this.imageAt,
    required this.labelAt,
    required this.placeholderIcon,
    required this.onTap,
    this.detailsBuilder,
    this.detailsHeight = 0,
    this.autoScrollEnabled,
  });

  final int itemCount;
  final String Function(int) imageAt;
  final String Function(int) labelAt;
  final IconData placeholderIcon;
  final void Function(int) onTap;
  final IndexedWidgetBuilder? detailsBuilder;
  final double detailsHeight;
  final bool? autoScrollEnabled;
  static const _itemWidth = 88.0;
  static const _itemSpacing = 10.0;

  @override
  Widget build(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(11) * 1.25 * 3;
    final extraHeight = detailsBuilder == null ? 0 : detailsHeight + 4;

    return SizedBox(
      height: (98 + labelHeight).clamp(140.0, double.infinity) + extraHeight,
      child: autoScrollEnabled == null || itemCount == 0
          ? _buildList(context)
          : SlowAutoScroll(
              enabled: autoScrollEnabled!,
              cycleExtent: itemCount * (_itemWidth + _itemSpacing),
              contentExtent:
                  itemCount * (_itemWidth + _itemSpacing) - _itemSpacing + 32,
              builder: (context, controller, repetitions) => _buildList(
                context,
                controller: controller,
                repetitions: repetitions,
              ),
            ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    ScrollController? controller,
    int repetitions = 1,
  }) => ListView.separated(
    controller: controller,
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    itemCount: itemCount * repetitions,
    separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
    itemBuilder: (context, index) {
      final i = index % itemCount;
      return InkWell(
        onTap: () => onTap(i),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        child: SizedBox(
          width: _itemWidth,
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: SFColors.border),
                  borderRadius: BorderRadius.circular(SFMetrics.radius),
                ),
                child: SFImage(
                  url: imageAt(i),
                  width: 80,
                  height: 80,
                  radius: SFMetrics.radius,
                  placeholderIcon: placeholderIcon,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      labelAt(i),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detailsBuilder != null) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        height: detailsHeight,
                        child: detailsBuilder!(context, i),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
