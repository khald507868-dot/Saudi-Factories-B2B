// ============================================================
//  صفحة المنتج
//
//  الإضافة للسلة لا تنقل المستخدم إلى السلة — يواصل التسوّق،
//  ويظهر شريط سفلي بعدد ما في السلة مقروءاً من الخادم لا من
//  عدّاد محلي.
// ============================================================

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/commerce_service.dart';
import '../services/factory_service.dart';
import '../services/messages_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import 'chat_page.dart';
import 'shell.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product});

  final SFProduct product;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  late int _quantity;
  bool _busy = false;
  int _cartCount = 0;

  @override
  void initState() {
    super.initState();
    _quantity = widget.product.moq ?? 1;
    _refreshCartCount();
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
      await SFCommerce.addToCart(widget.product.id, _quantity);
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
    final factoryId = widget.product.factoryId;
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
            // نص مبدئي يشرح عن أي منتج يسأل العميل.
            draft:
                '${context.t('product_draft_inquiry')} '
                '${widget.product.name}\n'
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
    final p = widget.product;
    final factoryName = (p.raw['factories'] as Map?)?['name'] as String? ?? '';

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(
        title: Text(
          p.name.isEmpty ? i18n.t('app_title') : p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        children: [
          SFImage(url: p.image, height: 260, radius: 0),
          Padding(
            padding: const EdgeInsets.all(16),
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
                if (factoryName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    factoryName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: SFColors.muted2,
                    ),
                  ),
                ],
                if (p.price > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${p.price.toStringAsFixed(2)} ر.س',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: SFColors.midGreen,
                    ),
                  ),
                ],
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _DetailsCard(
                    title: i18n.t('product_description'),
                    child: Text(
                      p.description,
                      style: const TextStyle(fontSize: 14, height: 1.8),
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'الكمية',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton.outlined(
                      onPressed: _quantity > (p.moq ?? 1)
                          ? () => setState(() => _quantity--)
                          : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '$_quantity',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _quantity >= 100000
                          ? null
                          : () => setState(() => _quantity++),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _contact,
                  icon: const Icon(Icons.chat_bubble_outline, size: 19),
                  label: Text(i18n.t('msg_contact_btn')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: SFColors.darkGreen,
                    side: const BorderSide(color: SFColors.darkGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SFMetrics.radius),
                    ),
                  ),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
                  onPressed: _busy ? null : _addToCart,
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
            width: 112,
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
