// ============================================================
//  السلة — مقابل app-cart.html
//
//  الكتابة متفائلة مع مصالحة من الخادم: زرّا − و + يعيدان
//  الرسم فوراً، ثم يُرسَل تعديل واحد بعد 400 مللي لدفعة
//  الضغطات. وإن رفض الخادم، يُعاد التحميل منه — فهو المرجع.
//
//  الحذف غير مؤجَّل: لا رجعة فيه فيُنفَّذ فوراً.
//
//  المجموع يُحسب في الخادم عند إنشاء الطلب؛ ما يظهر هنا عرض
//  فقط. الدفع يدوي بقرار المالك — لا بوابة دفع في التطبيق.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/commerce_service.dart';
import '../widgets/common.dart';
import 'shell.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  List<CartItem> _items = [];
  bool _loading = true;
  bool _ordering = false;
  Object? _error;

  /// تعديلات كمية بانتظار الإرسال — تُدفع قبل إنشاء الطلب.
  final Map<int, int> _pending = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AuthService.instance.isSignedIn) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await SFCommerce.loadCart();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  double get _total =>
      _items.fold<double>(0, (sum, i) => sum + i.lineTotal);

  void _changeQuantity(CartItem item, int delta) {
    final next = item.quantity + delta;
    if (next < 1) return;

    setState(() {
      _items = _items
          .map((i) => i.id == item.id ? i.copyWith(quantity: next) : i)
          .toList();
      _pending[item.id] = next;
    });

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
  }

  /// يرسل التعديلات المؤجّلة؛ عند الرفض يُعاد التحميل من الخادم.
  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final batch = Map<int, int>.from(_pending);
    _pending.clear();

    try {
      for (final entry in batch.entries) {
        await SFCommerce.setQuantity(entry.key, entry.value);
      }
      if (!mounted) return;
      AppShell.of(context)?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
      await _load();
    }
  }

  Future<void> _remove(CartItem item) async {
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    try {
      await SFCommerce.removeItem(item.id);
      if (mounted) AppShell.of(context)?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
      await _load();
    }
  }

  Future<void> _checkout() async {
    if (_items.isEmpty) return;

    // الخادم يرفض خلط مصنعين في طلب واحد، فنتحقّق قبل الإرسال.
    final factoryIds = _items.map((i) => i.factoryId).toSet();
    if (factoryIds.length > 1) {
      showSFError(
        context,
        Exception('لا يمكن طلب منتجات من أكثر من مصنع في طلب واحد.'),
      );
      return;
    }
    final factoryId = factoryIds.first;
    if (factoryId == null) return;

    setState(() => _ordering = true);
    try {
      // تُدفع التعديلات المؤجّلة أولاً حتى لا يُبنى الطلب على
      // كمية لم يرها الخادم بعد.
      _debounce?.cancel();
      await _flush();
      await SFCommerce.createOrder(factoryId);
      if (!mounted) return;
      showSFMessage(context, context.t('cart_order_sent'));
      await _load();
      if (mounted) AppShell.of(context)?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    if (!AuthService.instance.isSignedIn) {
      return Scaffold(
        backgroundColor: SFColors.pageBg,
        appBar: SFTopBar(title: i18n.t('cart_page_heading')),
        body: SFStateView(
          message: 'يجب تسجيل الدخول للتسوق',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('cart_page_heading')),
      body: _buildBody(i18n),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: SFColors.white,
                  border: Border(top: BorderSide(color: SFColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          i18n.t('cart_total_label'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_total.toStringAsFixed(2)} ر.س',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: SFColors.midGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _ordering ? null : _checkout,
                      child: _ordering
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: SFColors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(i18n.t('cart_checkout_btn')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody(I18n i18n) {
    if (_loading) {
      return SFStateView(message: i18n.t('fx_loading'), loading: true);
    }
    if (_error != null) {
      return SFStateView(
        message: i18n.t('fx_failed'),
        icon: Icons.cloud_off,
        onRetry: _load,
      );
    }
    if (_items.isEmpty) {
      return SFStateView(
        message: i18n.t('cart_empty_title'),
        icon: Icons.shopping_cart_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: SFColors.midGreen,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = _items[i];
          return _CartRow(
            item: item,
            onIncrement: () => _changeQuantity(item, 1),
            onDecrement: () => _changeQuantity(item, -1),
            onRemove: () => _remove(item),
          );
        },
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SFColors.white,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SFImage(url: item.image, width: 64, height: 64, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                if (item.factoryName.isNotEmpty)
                  Text(
                    item.factoryName,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: SFColors.muted2,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${item.price.toStringAsFixed(2)} ر.س',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: SFColors.midGreen,
                      ),
                    ),
                    const Spacer(),
                    _QtyButton(icon: Icons.remove, onTap: onDecrement),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _QtyButton(icon: Icons.add, onTap: onIncrement),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline,
                color: SFColors.danger, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: SFColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: SFColors.darkGreen),
      ),
    );
  }
}
