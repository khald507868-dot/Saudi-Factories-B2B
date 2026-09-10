// ============================================================
//  صفحة المنتج
//
//  الإضافة للسلة لا تنقل المستخدم إلى السلة — يواصل التسوّق،
//  ويظهر شريط سفلي بعدد ما في السلة مقروءاً من الخادم لا من
//  عدّاد محلي.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/currency.dart';
import '../core/pricing.dart';
import '../services/auth_service.dart';
import '../services/commerce_service.dart';
import '../services/factory_service.dart';
import '../services/messages_service.dart';
import '../services/favorites_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/product_reviews.dart';
import '../widgets/price_text.dart';
import 'factory_page.dart';
import 'chat_page.dart';
import 'shell.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product});

  final SFProduct product;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final _quantityInput = TextEditingController();
  SFProduct? _currentProduct;
  bool _loading = true;
  bool _missing = false;
  Object? _loadError;
  bool _favorite = false;
  bool _favoriteBusy = false;
  SFProduct get _product => _currentProduct ?? widget.product;
  late int _quantity;
  bool _busy = false;
  int _cartCount = 0;
  int _galleryPage = 0;

  @override
  void initState() {
    super.initState();
    _quantity = widget.product.moq ?? 1;
    _quantityInput.text = '$_quantity';
    _loadProduct();
    _refreshCartCount();
  }

  @override
  void dispose() {
    _quantityInput.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final product = await FactoryService.productById(widget.product.id);
      if (!mounted) return;
      setState(() {
        _currentProduct = product;
        _missing = product == null;
        _loading = false;
      });
      if (product != null) _setQuantity(_quantity);
      if (product != null && AuthService.instance.isSignedIn) {
        try {
          final favorite = await SFFavorites.isFavorite(product.id);
          if (mounted) setState(() => _favorite = favorite);
        } catch (_) {
          /* تبقى تفاصيل المنتج متاحة. */
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  void _setQuantity(int value) {
    setState(
      () =>
          _quantity = value.clamp((_product.moq ?? 1).clamp(1, 100000), 100000),
    );
    _quantityInput.text = '$_quantity';
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favoriteBusy = true);
    try {
      final favorite = await SFFavorites.toggle(
        _product.id,
        isFavoriteNow: _favorite,
      );
      if (mounted) setState(() => _favorite = favorite);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _refreshCartCount() async {
    if (!AuthService.instance.isSignedIn) return;
    try {
      final items = await SFCommerce.loadCart();
      if (!mounted) return;
      setState(() {
        _cartCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
      });
    } catch (_) {
      // العدّاد ثانوي — لا نُظهر خطأً بسببه.
    }
  }

  Future<void> _addToCart() async {
    if (!AuthService.instance.isSignedIn) {
      showSFError(context, Exception('يجب تسجيل الدخول للتسوق'));
      return;
    }
    setState(() => _busy = true);
    try {
      _setQuantity(int.tryParse(_quantityInput.text) ?? _quantity);
      await SFCommerce.addToCart(_product.id, _quantity);
      if (!mounted) return;
      showSFMessage(context, context.t('product_added_to_cart'));
      await _refreshCartCount();
      AppShell.active?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact() async {
    final factoryId = _product.factoryId;
    if (factoryId <= 0) return;
    if (!AuthService.instance.isSignedIn) {
      showSFError(context, Exception('يجب تسجيل الدخول للمراسلة'));
      return;
    }
    try {
      final thread = await SFMessages.ensureFactoryConversation(factoryId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: thread.conversationId,
            title: thread.name,
            product: SFProductAttachment(
              id: _product.id,
              name: _product.name,
              image: _product.image,
              price: _product.unitPrice(_quantity),
            ),
            // نص مبدئي يشرح عن أي منتج يسأل العميل.
            draft:
                '${context.t('product_draft_inquiry')} '
                '${context.t('product_draft_qty')} $_quantity',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final p = _product;
    final factoryName = (p.raw['factories'] as Map?)?['name'] as String? ?? '';

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed:
                _loading || _missing || _loadError != null || _favoriteBusy
                ? null
                : _toggleFavorite,
            tooltip: i18n.t(_favorite ? 'fav_remove' : 'fav_add'),
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
        title: Text(
          p.name.isEmpty ? i18n.t('app_title') : p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const _ProductSkeleton()
          : _loadError != null
          ? SFStateView(message: i18n.t('fx_failed'), onRetry: _loadProduct)
          : _missing
          ? SFStateView(message: i18n.t('prod_not_found'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: SFColors.white,
                    border: Border.all(color: SFColors.border),
                    borderRadius: BorderRadius.circular(SFMetrics.radius),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        p.images.isEmpty
                            ? const SFImage(url: '', radius: 0)
                            : PageView(
                                onPageChanged: (index) =>
                                    setState(() => _galleryPage = index),
                                children: [
                                  for (final url in p.images)
                                    InteractiveViewer(
                                      child: SFImage(
                                        url: url,
                                        fit: BoxFit.contain,
                                        radius: 0,
                                      ),
                                    ),
                                ],
                              ),
                        if (p.images.length > 1)
                          PositionedDirectional(
                            end: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: SFColors.white,
                                border: Border.all(color: SFColors.border),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_galleryPage + 1} / ${p.images.length}',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (factoryName.isNotEmpty)
                  Card(
                    child: ListTile(
                      tileColor: SFColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SFMetrics.radius),
                      ),
                      title: Text(
                        factoryName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: const Icon(
                        Icons.factory_outlined,
                        color: SFColors.midGreen,
                      ),
                      trailing:
                          (p.raw['factories'] as Map?)?['status'] == 'approved'
                          ? const Icon(Icons.verified, color: SFColors.midGreen)
                          : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FactoryPage(factoryId: p.factoryId),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SFColors.white,
                          border: Border.all(color: SFColors.border),
                          borderRadius: BorderRadius.circular(SFMetrics.radius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                height: 1.5,
                              ),
                            ),
                            if (p.unitPrice(_quantity) > 0) ...[
                              const SizedBox(height: 12),
                              SFPriceText(
                                SFCurrency.instance.format(
                                  p.unitPrice(_quantity),
                                ),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: SFColors.midGreen,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (p.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DetailsCard(
                          title: i18n.t('product_description'),
                          child: Text(
                            p.description,
                            style: const TextStyle(fontSize: 14, height: 1.65),
                          ),
                        ),
                      ],
                      if (p.material.isNotEmpty ||
                          p.sizes.isNotEmpty ||
                          p.colors.isNotEmpty ||
                          p.moq != null) ...[
                        const SizedBox(height: 12),
                        _DetailsCard(
                          title: i18n.t('product_specs'),
                          child: Column(
                            children: [
                              if (p.material.isNotEmpty)
                                _SpecRow(
                                  label: i18n.t('product_material'),
                                  value: p.material,
                                ),
                              if (p.sizes.isNotEmpty)
                                _SpecRow(
                                  label: i18n.t('product_sizes'),
                                  value: p.sizes,
                                ),
                              if (p.colors.isNotEmpty)
                                _SpecRow(
                                  label: i18n.t('product_colors'),
                                  value: p.colors,
                                ),
                              if (p.moq != null)
                                _SpecRow(
                                  label: i18n.t('product_moq'),
                                  value: '${p.moq} ${i18n.t('product_unit')}',
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (p.tiers.isNotEmpty) ...[
                        Text(
                          i18n.t('tier_pricing'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tier in p.tiers)
                              ChoiceChip(
                                selected:
                                    SFPriceCalculation.activeTier(
                                      p.tiers,
                                      _quantity,
                                    )?.min ==
                                    tier.min,
                                onSelected: (_) => _setQuantity(tier.min),
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${tier.min}${tier.max == null ? '+' : '–${tier.max}'} ${i18n.t('tier_piece')}',
                                    ),
                                    const SizedBox(height: 4),
                                    SFPriceText(
                                      SFCurrency.instance.format(tier.price),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              i18n.t('prod_quantity'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: _quantity > (p.moq ?? 1)
                                ? () => _setQuantity(_quantity - 1)
                                : null,
                            icon: const Icon(Icons.remove, size: 18),
                          ),
                          SizedBox(
                            width: 82,
                            child: TextField(
                              controller: _quantityInput,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              onChanged: (value) {
                                final next = int.tryParse(value);
                                if (next != null && next >= (p.moq ?? 1)) {
                                  _setQuantity(next);
                                }
                              },
                              onEditingComplete: () {
                                _setQuantity(
                                  int.tryParse(_quantityInput.text) ??
                                      _quantity,
                                );
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: _quantity >= 100000
                                ? null
                                : () => _setQuantity(_quantity + 1),
                            icon: const Icon(Icons.add, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _PurchaseAmounts(product: p, quantity: _quantity),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _contact,
                        icon: const Icon(Icons.chat_bubble_outline, size: 19),
                        label: Text(i18n.t('msg_contact_btn')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: SFColors.darkGreen,
                          side: const BorderSide(color: SFColors.darkGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SFMetrics.radius,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ProductReviews(productId: p.id),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _loading || _missing || _loadError != null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: SFColors.white,
                  border: Border(top: BorderSide(color: SFColors.border)),
                ),
                child: Row(
                  children: [
                    if (_cartCount > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: InkWell(
                          onTap: () {
                            AppShell.active?.goTo(SFTab.cart);
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.shopping_cart_outlined,
                                color: SFColors.darkGreen,
                              ),
                              Text(
                                '$_cartCount ${i18n.t('cart_items_count')}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: SFColors.muted2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _busy ||
                                p.unitPrice(_quantity) <= 0 ||
                                (p.raw['factories'] as Map?)?['status'] !=
                                    'approved'
                            ? null
                            : _addToCart,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: SFColors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(i18n.t('product_add_to_cart')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ProductSkeleton extends StatelessWidget {
  const _ProductSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Container(height: 260, color: SFColors.surfaceAlt),
      const SizedBox(height: 20),
      for (final width in [1.0, .7, .85])
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: width,
            child: Container(
              height: 22,
              margin: const EdgeInsets.only(bottom: 14),
              color: SFColors.surfaceAlt,
            ),
          ),
        ),
      const LinearProgressIndicator(),
    ],
  );
}

class _PurchaseAmounts extends StatelessWidget {
  const _PurchaseAmounts({required this.product, required this.quantity});
  final SFProduct product;
  final int quantity;
  @override
  Widget build(BuildContext context) {
    final currency = SFCurrency.instance;
    final estimate = SFOrderEstimate(
      currency.lineAmount(product.unitPrice(quantity), quantity),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SFColors.surfaceAlt,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in <String, double>{
            '${currency.format(product.unitPrice(quantity))} × $quantity':
                estimate.subtotal,
            context.t('order_shipping'): estimate.shipping,
            context.t('order_payment_fee'): estimate.paymentFee,
            context.t('order_vat'): estimate.vat,
            context.t('cart_total_label'): estimate.total,
          }.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: row.key.contains('×')
                        ? SFPriceText(row.key)
                        : Text(row.key),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: SFPriceText(
                      currency.format(row.value),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: row.key == context.t('cart_total_label')
                            ? 17
                            : 14,
                        fontWeight: row.key == context.t('cart_total_label')
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: SFColors.midGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            context.t('order_estimate_note'),
            style: const TextStyle(fontSize: 12, color: SFColors.muted2),
          ),
          if (currency.isForeign)
            Text(
              context.t('currency_note'),
              style: const TextStyle(fontSize: 12, color: SFColors.muted2),
            ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SFColors.white,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SFColors.muted2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}
